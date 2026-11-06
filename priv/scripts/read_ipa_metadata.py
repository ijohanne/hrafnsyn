#!/usr/bin/env python3
"""Read bounded app metadata; never extract or execute an uploaded app."""

import json
import os
import plistlib
import re
import signal
import stat
import struct
import sys
import unicodedata
import zipfile

MAX_IPA = 250 * 1024 * 1024
MAX_DIRECTORY = 16 * 1024 * 1024
MAX_PLIST = 1024 * 1024
APP_INFO = re.compile(r"Payload/[^/]+\.app/Info\.plist\Z")
METADATA_FIELDS = {
    "CFBundleIdentifier": 255,
    "CFBundleVersion": 64,
    "CFBundleDisplayName": 200,
    "CFBundleName": 200,
}


class BinaryMetadata:
    """Read only root dictionary strings, never materialize an object graph.

    A small binary plist can reference the same large data through many distinct
    object IDs. General plist decoders may allocate that data once per ID. This
    reader ignores unused values entirely and bounds every string it does read.
    """

    def __init__(self, data):
        if len(data) < 40 or data[:8] != b"bplist00":
            raise ValueError("invalid binary plist")
        _, offset_width, self.ref_width, count, self.root, table = struct.unpack(
            ">6sBBQQQ", data[-32:])
        if (not 1 <= offset_width <= 8 or not 1 <= self.ref_width <= 8
                or not 1 <= count <= 65536 or self.root >= count
                or count - 1 >= 1 << (8 * self.ref_width)
                or table < 8 or table + count * offset_width != len(data) - 32):
            raise ValueError("invalid binary table")
        self.data = data
        self.offsets = [int.from_bytes(data[index:index + offset_width], "big")
                        for index in range(table, len(data) - 32, offset_width)]
        ordered = sorted(set(self.offsets))
        if len(ordered) != count or ordered[0] < 8 or ordered[-1] >= table:
            raise ValueError("invalid binary offsets")
        self.ends = dict(zip(ordered, ordered[1:] + [table]))
        self.check_spans()

    def check_spans(self):
        """Validate serialized extents without decoding or copying their payloads."""
        for reference, offset in enumerate(self.offsets):
            marker = self.data[offset]
            kind, low = marker >> 4, marker & 15
            if kind in (4, 5, 6, 7, 10, 11, 12, 13):
                _, position, length, end = self.object(reference, (kind,), MAX_PLIST)
                width = {6: 2, 10: self.ref_width, 11: self.ref_width,
                         12: self.ref_width, 13: self.ref_width * 2}.get(kind, 1)
                size = length * width
            else:
                position, end = offset + 1, self.ends[offset]
                if marker in (0x00, 0x08, 0x09, 0x0F):
                    size = 0
                elif kind == 1 and low <= 4:
                    size = 1 << low
                elif marker in (0x22, 0x23, 0x33):
                    size = 4 if marker == 0x22 else 8
                elif kind == 8:
                    size = low + 1
                else:
                    raise ValueError("unsupported binary object")
            if position + size > end:
                raise ValueError("overlapping binary objects")

    def object(self, reference, expected_type, maximum):
        if not 0 <= reference < len(self.offsets):
            raise ValueError("invalid binary reference")
        offset = self.offsets[reference]
        end = self.ends[offset]
        marker = self.data[offset]
        if marker >> 4 not in expected_type:
            raise ValueError("invalid binary object")
        position = offset + 1
        length = marker & 15
        if length == 15:
            if position >= end or self.data[position] not in (0x10, 0x11, 0x12, 0x13):
                raise ValueError("invalid binary length")
            width = 1 << (self.data[position] & 15)
            position += 1
            if position + width > end:
                raise ValueError("truncated binary length")
            length = int.from_bytes(self.data[position:position + width], "big")
            position += width
        if length > maximum:
            raise ValueError("oversized binary object")
        return marker >> 4, position, length, end

    def string(self, reference, maximum):
        kind, position, length, end = self.object(reference, (5, 6), maximum * 2)
        width = 2 if kind == 6 else 1
        if position + length * width > end:
            raise ValueError("overlapping binary string")
        value = self.data[position:position + length * width].decode(
            "utf-16be" if kind == 6 else "ascii")
        if len(value) > maximum:
            raise ValueError("oversized binary string")
        return value

    def read(self):
        _, position, count, end = self.object(self.root, (13,), 4096)
        if position + count * 2 * self.ref_width > end:
            raise ValueError("overlapping binary dictionary")
        result = {}
        seen = set()
        for index in range(count):
            key_at = position + index * self.ref_width
            value_at = key_at + count * self.ref_width
            key_ref = int.from_bytes(self.data[key_at:key_at + self.ref_width], "big")
            value_ref = int.from_bytes(self.data[value_at:value_at + self.ref_width], "big")
            if value_ref >= len(self.offsets):
                raise ValueError("invalid binary reference")
            key = self.string(key_ref, 255)
            if key in seen:
                raise ValueError("duplicate binary key")
            seen.add(key)
            if key in METADATA_FIELDS:
                result[key] = self.string(value_ref, METADATA_FIELDS[key])
        return result


def reject_timeout(_signum, _frame):
    raise TimeoutError("metadata timeout")


def check_directory(source):
    """Bound the central directory before ZipFile allocates its entry objects."""
    source.seek(0, os.SEEK_END)
    size = source.tell()
    source.seek(max(0, size - 65557))
    tail = source.read(65557)
    position = tail.rfind(b"PK\x05\x06")
    if position < 0 or len(tail) - position < 22:
        raise ValueError("missing directory")
    values = struct.unpack_from("<4s4H2LH", tail, position)
    _, disk, directory_disk, disk_entries, entries, length, offset, comment = values
    if (disk or directory_disk or disk_entries != entries or entries == 65535
            or length > MAX_DIRECTORY or offset + length > size - len(tail) + position
            or len(tail) - position != 22 + comment):
        raise ValueError("unsupported directory")


def safe_name(name):
    return (name and not name.startswith("/") and "\\" not in name
            and "\0" not in name and ".." not in name.split("/"))


def text(value, maximum):
    if (not isinstance(value, str) or not value.strip() or len(value) > maximum
            or any(unicodedata.category(char).startswith("C") for char in value)):
        raise ValueError("invalid text")
    return value


def read(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_IPA:
            raise ValueError("invalid IPA")
        check_directory(source)
        with zipfile.ZipFile(source) as archive:
            entries = archive.infolist()
            names = [entry.filename for entry in entries]
            if not all(safe_name(name) for name in names) or len(set(names)) != len(names):
                raise ValueError("unsafe archive")
            candidates = [entry for entry in entries if APP_INFO.fullmatch(entry.filename)]
            if len(candidates) != 1:
                raise ValueError("ambiguous app")
            entry = candidates[0]
            if (entry.file_size > MAX_PLIST or entry.compress_size > MAX_PLIST
                    or entry.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
                    or entry.flag_bits & 1):
                raise ValueError("unsupported plist")
            with archive.open(entry) as stream:
                data = stream.read(MAX_PLIST + 1)
            if len(data) > MAX_PLIST:
                raise ValueError("oversized plist")
    values = BinaryMetadata(data).read() if data.startswith(b"bplist") else plistlib.loads(data)
    if not isinstance(values, dict):
        raise ValueError("invalid plist")
    bundle = text(values.get("CFBundleIdentifier"), 255)
    version = text(values.get("CFBundleVersion"), 64)
    title = text(values.get("CFBundleDisplayName", values.get("CFBundleName", bundle)), 200)
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*", bundle):
        raise ValueError("invalid identifier")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.]*", version):
        raise ValueError("invalid version")
    return {"bundle_identifier": bundle, "bundle_version": version, "title": title}


def main():
    signal.signal(signal.SIGALRM, reject_timeout)
    signal.alarm(5)
    try:
        if len(sys.argv) != 2:
            return 2
        result = read(sys.argv[1])
        print(json.dumps(result, ensure_ascii=True))
        return 0
    except (OSError, ValueError, KeyError, TypeError, OverflowError, RecursionError,
            RuntimeError, zipfile.BadZipFile, EOFError, struct.error):
        # No paths, archive metadata, identifiers, or exception bodies in logs.
        return 2
    finally:
        signal.alarm(0)


if __name__ == "__main__":
    sys.exit(main())

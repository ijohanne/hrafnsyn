#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <Security/CMSEncoder.h>

static void check(OSStatus status, const char *stage) {
  if (status != errSecSuccess) { fprintf(stderr, "%s: %d\n", stage, (int)status); exit(1); }
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc != 4) return 2;
    NSData *p12 = [NSData dataWithContentsOfFile:@(argv[1])];
    NSData *content = [NSData dataWithContentsOfFile:@(argv[2])];
    if (!p12 || !content) return 3;
    // Explicit memory-only import: do not read or write any user keychain.
    NSDictionary *options = @{(__bridge id)kSecImportToMemoryOnly: @YES,
                             (__bridge id)kSecImportExportPassphrase: @"synthetic-fixture"};
    CFArrayRef items = NULL;
    check(SecPKCS12Import((__bridge CFDataRef)p12, (__bridge CFDictionaryRef)options, &items), "import");
    CFDictionaryRef first = CFArrayGetValueAtIndex(items, 0);
    SecIdentityRef identity = (SecIdentityRef)CFDictionaryGetValue(first, kSecImportItemIdentity);
    CMSEncoderRef encoder = NULL;
    check(CMSEncoderCreate(&encoder), "create");
    check(CMSEncoderAddSigners(encoder, identity), "signer");
    check(CMSEncoderSetCertificateChainMode(encoder, kCMSCertificateSignerOnly), "chain");
    check(CMSEncoderSetHasDetachedContent(encoder, false), "attached");
    check(CMSEncoderUpdateContent(encoder, content.bytes, content.length), "content");
    CFDataRef encoded = NULL;
    check(CMSEncoderCopyEncodedContent(encoder, &encoded), "encode");
    BOOL written = [(__bridge NSData *)encoded writeToFile:@(argv[3]) atomically:YES];
    printf("Synthetic Apple CMS: %ld bytes\n", CFDataGetLength(encoded));
    CFRelease(encoded); CFRelease(encoder); CFRelease(items);
    return written ? 0 : 4;
  }
}

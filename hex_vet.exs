%{
  policy: %{criteria_required: :safe_to_deploy, block_on_unvetted: :new_only},
  imports: %{},
  audits: [
    %{
      version: "0.3.1",
      reviewer: "ij@opsplaza.com",
      package: "dns_cluster",
      criteria: :safe_to_deploy,
      reviewed_at: ~D[2026-10-16],
      notes:
        "User explicitly accepted this Rule 6 publisher change as safe to deploy on 2026-10-16. chrismccord -> josevalim; both current Hex owners, upstream release commit by josevalim. All eight native rules ran on old/new tarballs; no other native findings."
    },
    %{
      version: "4.1.0",
      reviewer: "ij@opsplaza.com",
      package: "geo",
      criteria: :safe_to_deploy,
      reviewed_at: ~D[2026-10-16],
      notes:
        "User explicitly accepted this Rule 6 publisher change as safe to deploy on 2026-10-16. tylerayoung -> axelson; Felt organization owns Hex package, upstream v4.1.0 release authored by axelson. All eight native rules ran on old/new tarballs; no other native findings."
    },
    %{
      version: "2.4.1",
      reviewer: "ij@opsplaza.com",
      package: "phoenix_pubsub",
      criteria: :safe_to_deploy,
      reviewed_at: ~D[2026-10-16],
      notes:
        "User explicitly accepted this Rule 6 publisher change as safe to deploy on 2026-10-16. josevalim -> steffend; both current Hex owners, upstream tag commit by SteffenDE. All eight native rules ran on old/new tarballs; no other native findings."
    }
  ]
}

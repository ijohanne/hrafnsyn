%{
  policy: %{criteria_required: :safe_to_deploy, block_on_unvetted: :new_only},
  imports: %{},
  audits: [
    %{
      version: "0.3.1",
      package: "dns_cluster",
      criteria: :safe_to_deploy,
      reviewer: "ij@opsplaza.com",
      reviewed_at: ~D[2026-10-16],
      notes:
        "User explicitly accepted this Rule 6 publisher change as safe to deploy on 2026-10-16. chrismccord -> josevalim; both current Hex owners, upstream release commit by josevalim. All eight native rules ran on old/new tarballs; no other native findings."
    },
    %{
      version: "4.1.0",
      package: "geo",
      criteria: :safe_to_deploy,
      reviewer: "ij@opsplaza.com",
      reviewed_at: ~D[2026-10-16],
      notes:
        "User explicitly accepted this Rule 6 publisher change as safe to deploy on 2026-10-16. tylerayoung -> axelson; Felt organization owns Hex package, upstream v4.1.0 release authored by axelson. All eight native rules ran on old/new tarballs; no other native findings."
    },
    %{
      version: "2.4.1",
      package: "phoenix_pubsub",
      criteria: :safe_to_deploy,
      reviewer: "ij@opsplaza.com",
      reviewed_at: ~D[2026-10-16],
      notes:
        "User explicitly accepted this Rule 6 publisher change as safe to deploy on 2026-10-16. josevalim -> steffend; both current Hex owners, upstream tag commit by SteffenDE. All eight native rules ran on old/new tarballs; no other native findings."
    },
    %{
      version: "4.4.0",
      package: "phoenix_html",
      criteria: :safe_to_deploy,
      reviewer: "ij@opsplaza.com",
      reviewed_at: ~D[2026-11-06],
      notes:
        "User explicitly approved Phoenix.HTML 4.4.0 for deployment on 2026-11-06 after reviewing the Rule 6 publisher change josevalim -> steffend. Hex lists steffend as a current owner; upstream v4.4.0 points to GitHub-verified commit 15ba2aa signed by SteffenDE. All eight native rules ran on both release tarballs; no other findings. Reviewed source changes add attribute-name validation (CVE-2026-117645) and JSON escaping. https://hex.pm/packages/phoenix_html https://github.com/phoenixframework/phoenix_html/releases/tag/v4.4.0"
    }
  ]
}

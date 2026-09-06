// Embed the app icon into the Windows executable (no-op elsewhere).
fn main() {
    println!("cargo:rerun-if-changed=assets/mdr.ico");
    #[cfg(windows)]
    {
        let mut res = winresource::WindowsResource::new();
        res.set_icon("assets/mdr.ico");
        res.set("ProductName", "mdr (oxgenet fork)");
        res.set("FileDescription", "Markdown viewer/editor with Mermaid and CJK-aware rendering");
        res.set("LegalCopyright", "Copyright (c) 2026 Clever Cloud; Copyright (c) 2026 oxge.net");
        if let Err(e) = res.compile() {
            println!("cargo:warning=windows resource not embedded: {e}");
        }
    }
}

fn main() {
    // Embed Windows manifest for admin elevation detection
    #[cfg(windows)]
    {
        embed_resource::compile("nactl.rc", embed_resource::NONE);
    }
}

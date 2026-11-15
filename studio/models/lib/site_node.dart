/// What a node of the Sites map is: the site on screen, a broker above or
/// below, a platform it sends to, a connection that waits in quarantine, a
/// device of an external link, a site relayed below.
enum SiteNode { self, upstream, platform, downstream, waiting, device, relayed }

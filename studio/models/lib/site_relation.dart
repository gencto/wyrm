/// How a site the session reaches is related to the one it logged into:
/// it is that site, a site below it (perhaps through another), or an
/// upstream it connects to.
enum SiteRelation { self, downstream, upstream }

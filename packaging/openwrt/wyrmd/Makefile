# OpenWrt package `wyrmd`: the WYRM broker as a prebuilt binary (ADR 0051 §1).
#
# Nothing is compiled here. CI builds one static `aarch64-unknown-linux-musl` binary
# and packs it once per package architecture of the boards:
#
#   make package/wyrmd/compile WYRMD_BIN=/path/to/wyrmd WYRMD_VERSION=0.9.0
#
# See ../README.md for what the files do.

include $(TOPDIR)/rules.mk

PKG_NAME:=wyrmd
PKG_VERSION:=$(if $(WYRMD_VERSION),$(WYRMD_VERSION),0.1.0)
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=WYRM <https://github.com/gencto/wyrm>

# a static binary that is stripped where it is built: OpenWrt's strip leaves it alone
STRIP:=:
RSTRIP:=:

include $(INCLUDE_DIR)/package.mk

# USERID: the broker's user and group. 787 is this package's own choice among the fixed
# ids below 65536 (from there OpenWrt hands out ids itself); OpenWrt keeps no registry for
# packages outside its feeds. It is free in the pinned release and its feeds
# (packaging/images/README.md, "The broker's user"). A board image takes this package as
# files, so there packaging/images/files/etc/uci-defaults/80-wyrm-user makes the user.
define Package/wyrmd
  SECTION:=net
  CATEGORY:=Network
  TITLE:=WYRM broker
  URL:=https://wyrm.gencto.uk
  DEPENDS:=+jsonfilter
  USERID:=wyrm=787:wyrm=787
endef

define Package/wyrmd/description
  The WYRM broker with its procd service, the first boot of a board image (the
  configuration of the image's config region) and the role of a plain host.
endef

define Package/wyrmd/conffiles
/etc/wyrm/wyrmd.json5
endef

define Build/Prepare
	@[ -f "$(WYRMD_BIN)" ] || { \
		echo "wyrmd: set WYRMD_BIN to the built binary (aarch64-unknown-linux-musl)" >&2; \
		exit 1; \
	}
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/wyrmd/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/usr/libexec/wyrm $(1)/usr/share/wyrm/seed
	$(INSTALL_DIR) $(1)/etc/init.d $(1)/etc/uci-defaults $(1)/etc/wyrm
	$(INSTALL_DIR) $(1)/etc/hotplug.d/ntp $(1)/lib/upgrade/keep.d $(1)/srv/wyrm
	$(INSTALL_BIN) $(WYRMD_BIN) $(1)/usr/bin/wyrmd
	$(INSTALL_BIN) ./files/usr/libexec/wyrm/first-boot.sh $(1)/usr/libexec/wyrm/
	$(INSTALL_BIN) ./files/usr/libexec/wyrm/run.sh $(1)/usr/libexec/wyrm/
	$(INSTALL_BIN) ./files/etc/init.d/wyrmd $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/etc/uci-defaults/90-wyrm-host $(1)/etc/uci-defaults/
	$(INSTALL_DATA) ./files/etc/hotplug.d/ntp/20-wyrm-time $(1)/etc/hotplug.d/ntp/
	$(INSTALL_DATA) ./files/lib/upgrade/keep.d/wyrm $(1)/lib/upgrade/keep.d/
	$(INSTALL_CONF) ./files/etc/wyrm/wyrmd.json5 $(1)/etc/wyrm/
endef

$(eval $(call BuildPackage,wyrmd))

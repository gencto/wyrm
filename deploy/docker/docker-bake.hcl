# Every image of deploy/docker/Dockerfile from one build stage (deploy/docker/README.md).
# Every target passes the same LINKS, SIMS and JOBS, so BuildKit runs the Rust build once per
# platform and each image copies its binary out of it. Run from the repository root.
#
#   docker buildx bake -f deploy/docker/docker-bake.hcl --load                  # wyrm/*:local
#   docker buildx bake -f deploy/docker/docker-bake.hcl --set '*.platform=linux/arm/v7' --load
#   LINKS=modbus SIMS= docker buildx bake -f deploy/docker/docker-bake.hcl wyrmd link tools
#   docker buildx bake -f deploy/docker/docker-bake.hcl --print                 # what it builds
#
# Names: <NAMESPACE>/wyrmd, <NAMESPACE>/wyrm-link-<link>, <NAMESPACE>/wyrm-sim-<sim>,
# <NAMESPACE>/wyrm-tools. NAMESPACE `wyrm` and TAG `local` for a build on this host;
# .github/workflows/docker-images.yml builds `genctouk` for Docker Hub (TAG empty: pushed by
# digest, tagged when the platforms are merged).

variable "NAMESPACE" {
  default = "wyrm"
}
variable "TAG" {
  default = "local"
}
# The links built as their own images (package suffix of wyrm-link-<name>), and the simulators.
variable "LINKS" {
  default = "modbus snmp s7 bacnet knx opcua http prometheus mqtt postgres mysql mongodb influxdb dynamodb s3 gdrive webdav localfs uplink alarm dql scheduler"
}
variable "SIMS" {
  default = "modbus snmp"
}
# Jobs of the Rust build; wyrmd's link alone takes about 3 GB.
variable "JOBS" {
  default = "2"
}
# OCI labels; the workflow sets them.
variable "VERSION" {
  default = ""
}
variable "REVISION" {
  default = ""
}

function "image" {
  params = [name]
  result = TAG == "" ? "${NAMESPACE}/${name}" : "${NAMESPACE}/${name}:${TAG}"
}

# An empty LINKS or SIMS leaves its images out.
group "default" {
  targets = concat(
    ["wyrmd", "tools"],
    length(compact(split(" ", LINKS))) > 0 ? ["link"] : [],
    length(compact(split(" ", SIMS))) > 0 ? ["sim"] : [],
  )
}

target "_common" {
  context    = "."
  dockerfile = "deploy/docker/Dockerfile"
  args = {
    LINKS = LINKS
    SIMS  = SIMS
    JOBS  = JOBS
  }
  labels = {
    "org.opencontainers.image.source"   = "https://github.com/gencto/wyrm"
    "org.opencontainers.image.url"      = "https://github.com/gencto/wyrm/tree/main/deploy/docker"
    "org.opencontainers.image.licenses" = "Apache-2.0"
    "org.opencontainers.image.vendor"   = "WYRM"
    "org.opencontainers.image.version"  = VERSION
    "org.opencontainers.image.revision" = REVISION
  }
}

target "wyrmd" {
  inherits = ["_common"]
  target   = "wyrmd"
  tags     = [image("wyrmd")]
  labels = {
    "org.opencontainers.image.title"       = "wyrmd"
    "org.opencontainers.image.description" = "The WYRM broker: router, admin, flow engine, gateway and built-in links"
  }
}

target "link" {
  name     = "link-${l}"
  matrix   = { l = compact(split(" ", LINKS)) }
  inherits = ["_common"]
  target   = "link"
  args     = { LINK = l }
  tags     = [image("wyrm-link-${l}")]
  labels = {
    "org.opencontainers.image.title"       = "wyrm-link-${l}"
    "org.opencontainers.image.description" = "The WYRM ${l} link as an external link (mTLS to the broker)"
  }
}

target "sim" {
  name     = "sim-${s}"
  matrix   = { s = compact(split(" ", SIMS)) }
  inherits = ["_common"]
  target   = "sim"
  args     = { SIM = s }
  tags     = [image("wyrm-sim-${s}")]
  labels = {
    "org.opencontainers.image.title"       = "wyrm-sim-${s}"
    "org.opencontainers.image.description" = "A ${s} device simulator for WYRM examples"
  }
}

target "tools" {
  inherits = ["_common"]
  target   = "tools"
  tags     = [image("wyrm-tools")]
  labels = {
    "org.opencontainers.image.title"       = "wyrm-tools"
    "org.opencontainers.image.description" = "wyr and wyrm-agent on Alpine, with a shell"
  }
}

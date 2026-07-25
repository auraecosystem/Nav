#!/usr/bin/ksh
#
# build_aix.ksh
#
# Production-grade AIX fileset packaging script.
#
# Usage:
#   ./build_aix.ksh <staging-directory>
#
# Expected:
#   build/aix/pkginfo
#
# Output:
#   build/aix/<PKG>.<NAME>.<VERSION>.<ARCH>.I
#   build/aix/<PKG>.<NAME>.<VERSION>.<ARCH>.template
#   build/aix/.toc
#
# Required commands:
#   ksh
#   du
#   find
#   chmod
#   chown
#   mkinstallp
#   inutoc
#   installp
#

set -u

###############################################################################
# Configuration
###############################################################################

SCRIPT_NAME=${0##*/}
BUILD=$(pwd)

if [ $# -ne 1 ]; then
    print "Usage: ${SCRIPT_NAME} <staging-directory>"
    exit 2
fi

TEMPDIR=$1

PKGINFO="${BUILD}/build/aix/pkginfo"
INFO="${BUILD}/build/aix/.info"
OUTPUT_DIR="${BUILD}/build/aix"

###############################################################################
# Utility functions
###############################################################################

die()
{
    print "ERROR: $*" >&2
    exit 1
}

log()
{
    print "==> $*"
}

require_command()
{
    command -v "$1" >/dev/null 2>&1 || \
        die "Required command not found: $1"
}

###############################################################################
# Validate environment
###############################################################################

log "Validating environment..."

[ -d "${TEMPDIR}" ] || \
    die "Staging directory does not exist: ${TEMPDIR}"

[ -f "${PKGINFO}" ] || \
    die "Package metadata not found: ${PKGINFO}"

require_command du
require_command find
require_command chmod
require_command chown
require_command mkinstallp
require_command inutoc
require_command installp

###############################################################################
# Load package metadata
###############################################################################

log "Loading package metadata..."

. "${PKGINFO}"

: "${PKG:?PKG is not defined in pkginfo}"
: "${NAME:?NAME is not defined in pkginfo}"
: "${VERSION:?VERSION is not defined in pkginfo}"
: "${VENDOR:?VENDOR is not defined in pkginfo}"
: "${ARCH:?ARCH is not defined in pkginfo}"

package="${PKG}"
name="${NAME}"
vrmf="${VERSION}"
descr="${VENDOR} ${NAME} for ${ARCH}"

###############################################################################
# Paths
###############################################################################

TEMPLATE="${INFO}/${PKG}.${NAME}.${vrmf}.template"
FILES="${TEMPDIR}/httpd-root"

###############################################################################
# Validate staging tree
###############################################################################

log "Validating staging tree..."

[ -d "${FILES}" ] || \
    die "Payload directory not found: ${FILES}"

for d in etc opt var
do
    [ -d "${TEMPDIR}/${d}/${NAME}" ] || \
        die "Required directory not found: ${TEMPDIR}/${d}/${NAME}"
done

[ -d "${TEMPDIR}/usr/share/man" ] || \
    die "Required directory not found: ${TEMPDIR}/usr/share/man"

###############################################################################
# Prepare output directories
###############################################################################

log "Preparing output directories..."

umask 022

mkdir -p "${INFO}" || \
    die "Unable to create ${INFO}"

rm -f "${TEMPLATE}"

touch "${TEMPLATE}" || \
    die "Unable to create template: ${TEMPLATE}"

###############################################################################
# Calculate package size requirements
###############################################################################

log "Calculating package size requirements..."

get_size()
{
    target=$1

    size=$(du -s "${target}" 2>/dev/null | awk '{print $1}')

    [ -n "${size}" ] || \
        die "Unable to calculate size for ${target}"

    print $((size + 1))
}

szetc=$(get_size "${TEMPDIR}/etc/${NAME}")
szopt=$(get_size "${TEMPDIR}/opt/${NAME}")
szvar=$(get_size "${TEMPDIR}/var/${NAME}")
szman=$(get_size "${TEMPDIR}/usr/share/man")

log "etc/${NAME}: ${szetc} blocks"
log "opt/${NAME}: ${szopt} blocks"
log "var/${NAME}: ${szvar} blocks"
log "usr/share/man: ${szman} blocks"

###############################################################################
# Normalize permissions and ownership
###############################################################################

log "Normalizing package permissions..."

cd "${TEMPDIR}/.." || \
    die "Unable to enter staging parent directory"

find "${FILES}" -type d -exec chmod og+rx {} \; || \
    die "Failed to set directory permissions"

chmod -R go+r "${FILES}" || \
    die "Failed to set package permissions"

chown -R 0:0 "${FILES}" || \
    die "Failed to set package ownership"

###############################################################################
# Generate AIX fileset template
###############################################################################

log "Generating AIX fileset template..."

cat > "${TEMPLATE}" <<EOF
Package Name: ${package}.${NAME}
Package VRMF: ${vrmf}.0
Update: N
Fileset
  Fileset Name: ${package}.${NAME}.rte
  Fileset VRMF: ${vrmf}.0
  Fileset Description: ${descr}
  USRLIBLPPFiles
  EOUSRLIBLPPFiles
  Bosboot required: N
  License agreement acceptance required: N
  Include license files in this package: N
  Requisites:
        Upsize: /usr/share/man ${szman};
        Upsize: /etc/${NAME} ${szetc};
        Upsize: /opt/${NAME} ${szopt};
        Upsize: /var/${NAME} ${szvar};
  USRFiles
EOF

###############################################################################
# Add payload file list
###############################################################################

log "Generating package file list..."

cd "${TEMPDIR}/.." || \
    die "Unable to enter staging parent directory"

find "${FILES}" -print | \
    sed "s#^${FILES}##" | \
    sed '/^$/d' >> "${TEMPLATE}" || \
    die "Failed to generate package file list"

###############################################################################
# Complete template
###############################################################################

cat >> "${TEMPLATE}" <<EOF
  EOUSRFiles
  ROOT Part: N
  ROOTFiles
  EOROOTFiles
  Relocatable: N
EOFileset
EOF

###############################################################################
# Copy template to build output
###############################################################################

log "Copying template to output directory..."

cp "${TEMPLATE}" "${OUTPUT_DIR}/" || \
    die "Failed to copy package template"

###############################################################################
# Build BFF fileset
###############################################################################

log "Building AIX BFF fileset..."

rm -rf "${TEMPDIR}/tmp"

mkdir -p "${TEMPDIR}/tmp" || \
    die "Unable to create temporary packaging directory"

mkinstallp \
    -d "${TEMPDIR}" \
    -T "${TEMPLATE}" || \
    die "mkinstallp failed"

###############################################################################
# Locate generated BFF
###############################################################################

BFF="${TEMPDIR}/tmp/${PKG}.${NAME}.${VERSION}.0.bff"

[ -f "${BFF}" ] || \
    die "Expected BFF file was not generated: ${BFF}"

###############################################################################
# Copy and rename final install image
###############################################################################

log "Installing generated BFF into output directory..."

cp "${BFF}" "${OUTPUT_DIR}/" || \
    die "Failed to copy BFF"

cd "${OUTPUT_DIR}" || \
    die "Unable to enter output directory"

FINAL_IMAGE="${PKG}.${NAME}.${VERSION}.${ARCH}.I"

rm -f "${FINAL_IMAGE}"

mv \
    "${PKG}.${NAME}.${VERSION}.0.bff" \
    "${FINAL_IMAGE}" || \
    die "Failed to rename BFF to ${FINAL_IMAGE}"

###############################################################################
# Generate AIX table of contents
###############################################################################

log "Generating AIX .toc..."

rm -f .toc

inutoc "${OUTPUT_DIR}" || \
    die "inutoc failed"

###############################################################################
# Verify generated fileset
###############################################################################

log "Verifying generated fileset..."

installp \
    -d "${OUTPUT_DIR}" \
    -ap "${PKG}.${NAME}" || \
    die "installp verification failed"

###############################################################################
# Display package information
###############################################################################

log "Displaying fileset information..."

installp \
    -d "${OUTPUT_DIR}" \
    -L || \
    die "Unable to list generated filesets"

###############################################################################
# Complete
###############################################################################

print ""
print "============================================================"
print "AIX PACKAGE BUILD COMPLETE"
print "============================================================"
print "Package : ${PKG}.${NAME}"
print "Version : ${VERSION}"
print "Arch    : ${ARCH}"
print "Image   : ${OUTPUT_DIR}/${FINAL_IMAGE}"
print "Template: ${OUTPUT_DIR}/$(basename "${TEMPLATE}")"
print "TOC     : ${OUTPUT_DIR}/.toc"
print "============================================================"

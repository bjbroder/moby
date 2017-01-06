#!/bin/bash
set -e

# usage: ./generate.sh [versions]
#    ie: ./generate.sh
#        to update all Dockerfiles in this directory
#    or: ./generate.sh
#        to only update fedora-23/Dockerfile
#    or: ./generate.sh fedora-newversion
#        to create a new folder and a Dockerfile within it

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

for version in "${versions[@]}"; do
	distro="${version%-*}"
	suite="${version##*-}"
	from="${distro}:${suite}"
	installer=yum
	if [[ "$distro" == "fedora" ]]; then
		installer=dnf
	fi

	mkdir -p "$version"
	echo "$version -> FROM $from"
	cat > "$version/Dockerfile" <<-EOF
		#
		# THIS FILE IS AUTOGENERATED; SEE "contrib/builder/rpm/ppc64le/generate.sh"!
		#

		FROM ppc64le/$from
	EOF

	echo >> "$version/Dockerfile"

	extraBuildTags='pkcs11'
	runcBuildTags=

	case "$from" in
		# add centos and opensuse tools install bits later
		fedora:*)
			echo "RUN ${installer} -y upgrade" >> "$version/Dockerfile"
			echo "RUN ${installer} install -y @development-tools fedora-packager" >> "$version/Dockerfile"
			;;
	esac

	# this list is sorted alphabetically; please keep it that way
	packages=(
		btrfs-progs-devel # for "btrfs/ioctl.h" (and "version.h" if possible)
		device-mapper-devel # for "libdevmapper.h"
		glibc-static
		libseccomp-devel # for "seccomp.h" & "libseccomp.so"
		libselinux-devel # for "libselinux.so"
		libtool-ltdl-devel # for pkcs11 "ltdl.h"
		pkgconfig # for the pkg-config command
		selinux-policy
		selinux-policy-devel
		sqlite-devel # for "sqlite3.h"
		systemd-devel # for "sd-journal.h" and libraries
		tar # older versions of dev-tools do not have tar
		git # required for containerd and runc clone
		cmake # tini build
	)

	# opensuse does not have the right libseccomp libs
	case "$from" in
		# add opensuse libseccomp package substitution when adding build support
		*)
			extraBuildTags+=' seccomp'
			runcBuildTags="seccomp selinux"
			;;
	esac

	case "$from" in
		# add opensuse btrfs package substitution when adding build support
		*)
			echo "RUN ${installer} install -y ${packages[*]}" >> "$version/Dockerfile"
			;;
	esac

	echo >> "$version/Dockerfile"

	awk '$1 == "ENV" && $2 == "GO_VERSION" { print; exit }' ../../../../Dockerfile >> "$version/Dockerfile"
	echo 'RUN curl -fsSL "https://golang.org/dl/go${GO_VERSION}.linux-ppc64le.tar.gz" | tar xzC /usr/local' >> "$version/Dockerfile"
	echo 'ENV PATH $PATH:/usr/local/go/bin' >> "$version/Dockerfile"
	echo >> "$version/Dockerfile"	

	echo 'ENV AUTO_GOPATH 1' >> "$version/Dockerfile"
	echo >> "$version/Dockerfile"

	# print build tags in alphabetical order
	buildTags=$( echo "selinux $extraBuildTags" | xargs -n1 | sort -n | tr '\n' ' ' | sed -e 's/[[:space:]]*$//' )

	echo "ENV DOCKER_BUILDTAGS $buildTags" >> "$version/Dockerfile"
	echo "ENV RUNC_BUILDTAGS $runcBuildTags" >> "$version/Dockerfile"
	echo >> "$version/Dockerfile"

done
# Packages the Linux binary the build job already produced. The build context
# is a directory holding that binary, not the source tree, so the image is a
# copy step rather than a compile.
#
# ubuntu:24.04 matches the runner pulpmesh is compiled on: the binary links
# against that release's glibc and libcrypt, both of which the base image ships.
FROM ubuntu:24.04

COPY pulpmesh /usr/local/bin/pulpmesh

# Sites are read and written under /site, so a bind mount there is all a
# container needs to build one.
WORKDIR /site

ENTRYPOINT ["/usr/local/bin/pulpmesh"]

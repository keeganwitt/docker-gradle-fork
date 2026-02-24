#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

_sed() {
  if sed --version > /dev/null 2>&1; then
    # GNU sed
    sed --regexp-extended --in-place "$@"
  else
    # BSD sed
    sed -Ei '' "$@"
  fi
}

get_graalvm_info() {
  local jdk_version=$1
  local version=$(curl --silent --location 'https://api.github.com/repos/graalvm/graalvm-ce-builds/releases?per_page=20&page=1' | jq --raw-output "map(select(.tag_name | contains(\"jdk-$jdk_version\"))) | .[0].tag_name | sub(\"jdk-\"; \"\")" | tr -d '\r')
  local amd64_sha=$(curl --fail --location --silent "https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-${version}/graalvm-community-jdk-${version}_linux-x64_bin.tar.gz" | sha256sum | cut -d' ' -f1)
  local aarch64_sha=$(curl --fail --location --silent "https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-${version}/graalvm-community-jdk-${version}_linux-aarch64_bin.tar.gz" | sha256sum | cut -d' ' -f1)
  echo "$version $amd64_sha $aarch64_sha"
}

update_dockerfile_graalvm() {
  local dockerfile=$1
  local version=$2
  local amd64_sha=$3
  local aarch64_sha=$4
  local prefix=${5:-""}

  _sed \
    -e "s/JAVA_${prefix}VERSION=[^ ]+/JAVA_${prefix}VERSION=${version}/" \
    -e "s/GRAALVM_${prefix}AMD64_DOWNLOAD_SHA256=[^ ]+/GRAALVM_${prefix}AMD64_DOWNLOAD_SHA256=${amd64_sha}/" \
    -e "s/GRAALVM_${prefix}AARCH64_DOWNLOAD_SHA256=[^ ]+/GRAALVM_${prefix}AARCH64_DOWNLOAD_SHA256=${aarch64_sha}/" \
    "$dockerfile"
}

print_graalvm_info() {
  local jdk_version=$1
  local version=$2
  local amd64_sha=$3
  local aarch64_sha=$4

  echo "Latest Graal ${jdk_version} version is ${version}"
  echo "Graal ${jdk_version} AMD64 hash is ${amd64_sha}"
  echo "Graal ${jdk_version} AARCH64 hash is ${aarch64_sha}"
  echo
}

BASE_VERSION=$(cat version.txt)
gradleVersion=$(curl --fail --show-error --silent --location "https://services.gradle.org/versions/$BASE_VERSION" |
 jq --raw-output '.[] | select(.snapshot==false and .nightly==false and .broken==false and .milestoneFor=="" and .rcFor=="") | .version' | sort --version-sort | tail -n1)

echo "Base version: $BASE_VERSION"
echo "Latest version: $gradleVersion"

sha=$(curl --fail --show-error --silent --location "https://downloads.gradle.org/distributions/gradle-${gradleVersion}-bin.zip.sha256")

_sed "s/ENV GRADLE_VERSION=.+$/ENV GRADLE_VERSION=${gradleVersion}/" ./*/Dockerfile
_sed "s/GRADLE_DOWNLOAD_SHA256=.+$/GRADLE_DOWNLOAD_SHA256=${sha}/" ./*/Dockerfile
_sed "s/expectedGradleVersion: .+$/expectedGradleVersion: '${gradleVersion}'/" .github/workflows/ci.yaml

if [ "$BASE_VERSION" -lt "7" ]; then
  # no GraalVM for Gradle 6.x
  exit 0
fi

read -r graal17Version graal17amd64Sha graal17aarch64Sha <<< "$(get_graalvm_info 17)"
update_dockerfile_graalvm ./jdk17-noble-graal/Dockerfile "$graal17Version" "$graal17amd64Sha" "$graal17aarch64Sha"
update_dockerfile_graalvm ./jdk17-jammy-graal/Dockerfile "$graal17Version" "$graal17amd64Sha" "$graal17aarch64Sha"
print_graalvm_info 17 "$graal17Version" "$graal17amd64Sha" "$graal17aarch64Sha"

if [ "$BASE_VERSION" -lt "8" ]; then
  # no GraalVM 21+ for Gradle 7.x
  exit 0
fi

read -r graal21Version graal21amd64Sha graal21aarch64Sha <<< "$(get_graalvm_info 21)"
update_dockerfile_graalvm ./jdk21-noble-graal/Dockerfile "$graal21Version" "$graal21amd64Sha" "$graal21aarch64Sha"
update_dockerfile_graalvm ./jdk21-jammy-graal/Dockerfile "$graal21Version" "$graal21amd64Sha" "$graal21aarch64Sha"
print_graalvm_info 21 "$graal21Version" "$graal21amd64Sha" "$graal21aarch64Sha"

if [ "$BASE_VERSION" -lt "9" ]; then
  read -r graal24Version graal24amd64Sha graal24aarch64Sha <<< "$(get_graalvm_info 24)"
  update_dockerfile_graalvm ./jdk24-noble-graal/Dockerfile "$graal24Version" "$graal24amd64Sha" "$graal24aarch64Sha"

  update_dockerfile_graalvm ./jdk-lts-and-current-graal/Dockerfile "$graal21Version" "$graal21amd64Sha" "$graal21aarch64Sha" "21_"
  update_dockerfile_graalvm ./jdk-lts-and-current-graal/Dockerfile "$graal24Version" "$graal24amd64Sha" "$graal24aarch64Sha" "24_"

  print_graalvm_info 24 "$graal24Version" "$graal24amd64Sha" "$graal24aarch64Sha"
else
  read -r graal25Version graal25amd64Sha graal25aarch64Sha <<< "$(get_graalvm_info 25)"
  update_dockerfile_graalvm ./jdk25-noble-graal/Dockerfile "$graal25Version" "$graal25amd64Sha" "$graal25aarch64Sha"

  update_dockerfile_graalvm ./jdk-lts-and-current-graal/Dockerfile "$graal25Version" "$graal25amd64Sha" "$graal25aarch64Sha" "LTS_"
  update_dockerfile_graalvm ./jdk-lts-and-current-graal/Dockerfile "$graal25Version" "$graal25amd64Sha" "$graal25aarch64Sha" "CURRENT_"

  print_graalvm_info 25 "$graal25Version" "$graal25amd64Sha" "$graal25aarch64Sha"
fi

# escape=`

ARG WINDOWS_VERSION=ltsc2019

# Builder Image - Windows Server Core
FROM mcr.microsoft.com/windows/servercore:$WINDOWS_VERSION as builder

RUN setx /M PATH "%PATH%;C:\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;C:\WinFlexBison"

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
WORKDIR /local

# Install Visual Studio 2019
ADD https://aka.ms/vs/16/release/vs_buildtools.exe /local/vs_buildtools.exe
ADD https://aka.ms/vs/16/release/channel /local/VisualStudio.chman

RUN Start-Process /local/vs_buildtools.exe `
    -ArgumentList '--quiet ', '--wait ', '--norestart ', '--nocache', `
    '--installPath C:\BuildTools', `
    '--channelUri C:\local\VisualStudio.chman', `
    '--installChannelUri C:\local\VisualStudio.chman', `
    '--add Microsoft.VisualStudio.Workload.VCTools', `
    '--includeRecommended'  -NoNewWindow -Wait;

ADD https://github.com/lexxmark/winflexbison/releases/download/v2.5.22/win_flex_bison-2.5.22.zip /local/win_flex_bison.zip

RUN Expand-Archive /local/win_flex_bison.zip -Destination /WinFlexBison; `
    Copy-Item -Path /WinFlexBison/win_bison.exe /WinFlexBison/bison.exe; `
    Copy-Item -Path /WinFlexBison/win_flex.exe /WinFlexBison/flex.exe;

# Technique from https://github.com/StefanScherer/dockerfiles-windows/blob/master/mongo/3.6/Dockerfile
WORKDIR /local
ADD https://aka.ms/vs/15/release/vc_redist.x64.exe /local/vc_redist.x64.exe

WORKDIR /fluent-bit/bin/
RUN Start-Process /local/vc_redist.x64.exe -ArgumentList '/install', '/quiet', '/norestart' -NoNewWindow -Wait; `
    Copy-Item -Path /Windows/System32/msvcp140.dll -Destination /fluent-bit/bin/; `
    Copy-Item -Path /Windows/System32/vccorlib140.dll -Destination /fluent-bit/bin/; `
    Copy-Item -Path /Windows/System32/vcruntime140.dll -Destination /fluent-bit/bin/;

# Build Fluent Bit from source - context must be the root of the Git repo
WORKDIR /src/build
COPY . /src/

RUN cmake -G "'Visual Studio 16 2019'" -DCMAKE_BUILD_TYPE=Release ../; `
    cmake --build . --config Release;

# Set up config files and binaries in single /fluent-bit hierarchy for easy copy in later stage
RUN New-Item -Path  /fluent-bit/etc/ -ItemType "directory"; `
    Copy-Item -Path /src/conf/fluent-bit-win32.conf /fluent-bit/etc/fluent-bit.conf; `
    Copy-Item -Path /src/conf/parsers.conf /fluent-bit/etc/; `
    Copy-Item -Path /src/conf/parsers_ambassador.conf /fluent-bit/etc/; `
    Copy-Item -Path /src/conf/parsers_java.conf /fluent-bit/etc/; `
    Copy-Item -Path /src/conf/parsers_extra.conf /fluent-bit/etc/; `
    Copy-Item -Path /src/conf/parsers_openstack.conf /fluent-bit/etc/; `
    Copy-Item -Path /src/conf/parsers_cinder.conf /fluent-bit/etc/; `
    Copy-Item -Path /src/conf/plugins.conf /fluent-bit/etc/; `
    Copy-Item -Path /src/build/bin/Release/fluent-bit.exe /fluent-bit/bin/; `
    Copy-Item -Path /src/build/bin/Release/fluent-bit.dll /fluent-bit/bin/;
#
# Runtime Image - Windows Server Core
#
FROM mcr.microsoft.com/windows/servercore:$WINDOWS_VERSION as runtime

ARG FLUENTBIT_VERSION=master
ARG IMAGE_CREATE_DATE
ARG IMAGE_SOURCE_REVISION

# Metadata as defined in OCI image spec annotations
# https://github.com/opencontainers/image-spec/blob/master/annotations.md
LABEL org.opencontainers.image.title="Fluent Bit" `
      org.opencontainers.image.description="Fluent Bit is an open source and multi-platform Log Processor and Forwarder which allows you to collect data/logs from different sources, unify and send them to multiple destinations. It's fully compatible with Docker and Kubernetes environments." `
      org.opencontainers.image.created=$IMAGE_CREATE_DATE `
      org.opencontainers.image.version=$FLUENTBIT_VERSION `
      org.opencontainers.image.authors="Eduardo Silva <eduardo@calyptia.com>" `
      org.opencontainers.image.url="https://hub.docker.com/r/fluent/fluent-bit" `
      org.opencontainers.image.documentation="https://docs.fluentbit.io/manual/" `
      org.opencontainers.image.vendor="Fluent Organization" `
      org.opencontainers.image.licenses="Apache-2.0" `
      org.opencontainers.image.source="https://github.com/fluent/fluent-bit" `
      org.opencontainers.image.revision=$IMAGE_SOURCE_REVISION

COPY --from=builder /fluent-bit /fluent-bit

RUN setx /M PATH "%PATH%;C:\fluent-bit\bin"

ENTRYPOINT [ "C:\fluent-bit\bin\fluent-bit.exe" ]
# Hadolint gets confused by Windows it seems
# hadolint ignore=DL3025
CMD [ "C:\fluent-bit\bin\fluent-bit.exe", "-c", "C:\fluent-bit\etc\fluent-bit.conf" ]

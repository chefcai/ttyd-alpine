FROM tsl0922/ttyd:alpine

# Add openssh-client for SSH tunneling support
RUN apk add --no-cache openssh-client

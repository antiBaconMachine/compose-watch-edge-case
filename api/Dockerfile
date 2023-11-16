FROM alpine
RUN apk add --update --no-cache netcat-openbsd
WORKDIR /app
COPY src .
CMD "./main.sh"
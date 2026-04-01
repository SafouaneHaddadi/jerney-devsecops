FROM node:20-alpine AS build

WORKDIR /app

COPY package*.json ./

RUN npm ci --only=production && npm cache clean --force

FROM node:20-alpine AS production

RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup

RUN apk add --no-cache dumb-init=1.2.5-r3

WORKDIR /app

COPY --from=build --chown=appuser:appgroup /app/node_modules ./node_modules

COPY --chown=appuser:appgroup src/ ./src/

USER appuser

EXPOSE 5000

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/index.js"]

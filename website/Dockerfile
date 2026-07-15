# Build the Astro site and serve it as static files with nginx.
# Context is website/ — see the Dokploy app config (project mousugu).

FROM node:22-alpine AS build
WORKDIR /site
# corepack picks the pnpm version from package.json's packageManager field;
# the env var lets it download that version without an interactive prompt.
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /site/dist /usr/share/nginx/html

FROM node:20-slim

WORKDIR /app
RUN npm install -g pnpm
COPY package.json ./
# pnpm-lock.yamlがあればコピー
RUN if [ -f "pnpm-lock.yaml" ]; then cp pnpm-lock.yaml .; fi
RUN pnpm install

COPY . .
EXPOSE 3000
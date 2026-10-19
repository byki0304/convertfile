# convert-engine: Node.js 22 + LibreOffice (headless) + H2Orestart + Pandoc + free fonts only.
FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    HOME=/tmp

# Fonts: SIL OFL 1.1 / Apache-2.0 only (Noto CJK, Nanum, Liberation, Carlito, Caladea).
RUN apt-get update && apt-get install -y --no-install-recommends \
      libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-java-common \
      default-jre-headless pandoc poppler-utils ca-certificates curl fontconfig \
      fonts-noto-cjk fonts-noto-cjk-extra fonts-nanum fonts-liberation2 \
      fonts-crosextra-carlito fonts-crosextra-caladea \
    && rm -rf /var/lib/apt/lists/*

# H2Orestart (Apache-2.0): lets LibreOffice read .hwp / .hwpx.
ARG H2O_URL=https://github.com/ebandal/H2Orestart/releases/latest/download/H2Orestart.oxt
RUN curl -fsSL -o /tmp/H2Orestart.oxt "$H2O_URL" \
    && unopkg add --shared --suppress-license /tmp/H2Orestart.oxt \
    && rm -f /tmp/H2Orestart.oxt

COPY config/fonts.conf /etc/fonts/local.conf
RUN fc-cache -f

WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
RUN node tool/check_fonts.js

USER node
EXPOSE 8080
CMD ["node", "server.js"]

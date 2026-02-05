# Flutter + Android SDK 一式入りのイメージを利用（ラク）
FROM ghcr.io/cirruslabs/flutter:stable

WORKDIR /app
COPY . .

# Android向けに最低限のセットアップ（念のため）
RUN flutter doctor -v

CMD ["bash"]
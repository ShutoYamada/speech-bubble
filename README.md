# 開発環境

- Windows OS(ホスト)
  - Flutter 3.38.3
  - Android Studio
  - Android SDK
  - WSL2 Ubuntu
    - Docker Desktop
      - Dart 3.10.1
      - Hono 4.0.0
      - Node.js 20.19.5
      - pnpm 9.17.1

## 開発環境の構成イメージ

※WSL上、コンテナ内でflutterを実行した場合に、Windows上のAndroid Emulatorを解決するのが難しかったので、以下のようにしている。

```
┌───────────────────────────────────────────────────────────────────┐
│                           Windows PC                              │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                       Windows (Host)                         │ │
│  │                                                             │ │
│  │  ・Flutter SDK（Windows版）                                 │ │
│  │  ・Android Studio                                           │ │
│  │  ・Android Emulator                                         │ │
│  │                                                             │ │
│  │  flutter run                                                │ │
│  │      │                                                      │ │
│  │      ▼                                                      │ │
│  │  Android Emulator                                           │ │
│  │      │  http://10.0.2.2:3000                                 │ │
│  └──────┼─────────────────────────────────────────────────────┘ │
│         │                                                         │
│         │  \\wsl$\Ubuntu\home\user\repo\apps\mobile               │
│         │  （WSL上のFlutterソースを直接参照）                     │
│         ▼                                                         │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                            WSL2                              │ │
│  │                                                             │ │
│  │  ┌───────────────────────────────────────────────────────┐ │ │
│  │  │                docker-compose                           │ │ │
│  │  │                                                       │ │ │
│  │  │  API (Hono / Express)                                 │ │ │
│  │  │    - Port: 3000                                       │ │ │
│  │  │                                                       │ │ │
│  │  └───────────────────────────────────────────────────────┘ │ │
│  │                                                             │ │
│  │  repo/                                                      │ │
│  │  ├─ apps/                                                   │ │
│  │  │  ├─ api/        ← docker-compose で起動                 │ │
│  │  │  └─ mobile/     ← Flutterソース（起動はしない）        │ │
│  │  └─ docker-compose.yml                                     │ │
│  │                                                             │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

# 事前に必要なもの

## Flutter SDK

Windows上にFlutter SDKをインストールしておく。
以下が動作するか確認。

```bash
flutter --version
```

## Androidエミュレータ

Windows上のAndroid StudioでAndroidエミュレータを起動しておく

# 実行方法

## API

WSL2上で実行する。

```bash
# 起動
docker compose up -d

# APIの起動
docker compose exec api pnpm dev
```

## Flutter

Windows上で実行する。

```bash
# WSL2上のFlutterソースをWindows上で参照できるようにする
cd \\wsl$\Ubuntu\home\username\path-to-speech-bubble\apps\mobile

# Flutterの起動
flutter run
```

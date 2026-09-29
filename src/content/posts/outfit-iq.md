---
title: "outfit-iq：拍张照，让 AI 给你的穿搭打个分"
description: "一个 Expo / React Native 写的跨平台 App：拍照后由视觉大模型打分，给出维度分析和改造建议。不接后端，API Key 只存在你手机里。"
date: 2026-06-21
repo: outfit-iq
tags: ["TypeScript", "React Native", "Expo", "AI"]
---

出门前站在镜子前纠结「这样穿行不行」？[outfit-iq](https://github.com/chilin11/outfit-iq) 是一个小玩具：**拍一张照，AI 给你打分，并告诉你怎么改**。iOS 和 Android 都能用。

## 效果

- 一张总评分卡，背景颜色随分数变化，还有等级徽章；
- 色彩、版型、层次、风格四个维度的进度条（详细模式再加一个「合身」）；
- 识别出的单品以彩色标签展示；
- 「造型师手记」：亮点、待改进、改造建议。

UI 默认是折叠的，**只露出最核心的信息**，想看细节再展开。

## 跑起来

```bash
npm install
npm start
```

手机装上 Expo Go 扫码即可。第一次进入时，在右上角「⚙ 设置」里填写：

- API Base URL：`https://api.anthropic.com`（或你自己的代理）
- API Key
- Model：比如 `claude-sonnet-4-5`

## 几个设计取舍

**不引第三方 UI 库。** 所有样式都用 `StyleSheet` 手写，主题完全可控，包体也小。

**不接后端。** API Key 存在本机 `AsyncStorage`，App 直接调用模型。如果担心 Key 泄露，可以用 Cloudflare Worker 做一层中转，把代理地址填进 Base URL。

**图片压到 512px / JPEG 0.5。** 对于穿搭评分来说足够清晰，base64 体积小，响应也快。

**用非流式请求。** 流式输出在各种第三方代理下不太稳定，一次性返回更简单可靠。我还加了 JSON 修复逻辑，防止模型输出被截断时整个结果解析失败。

## 打包给朋友用

```bash
npm install -g eas-cli
eas login
eas build --profile preview --platform android
```

几分钟后会得到一个 APK 下载链接，直接发给朋友安装。

## 接下来

历史记录列表（数据其实已经存下来了）、多角度分析、生成分享卡片……都在计划中。项目使用 MIT 协议，想一起做的话欢迎来提 PR。

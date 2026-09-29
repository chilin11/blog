---
title: "HivisionID-X：一条 docker run 就能拥有自己的 AI 证件照工作台"
description: "上传照片，调整构图和底色，下载标准照、高清照和打印排版照。我在 HivisionIDPhotos 的基础上重做了 Web 工作台、API 和智能构图。"
date: 2026-09-18
repo: HivisionID-X
tags: ["Python", "FastAPI", "AI", "Docker"]
---

拍证件照这件事，要么去照相馆，要么把自拍上传到来路不明的小程序。我想要一个**自己部署、照片不离开自己机器**的方案，于是有了 [HivisionID-X](https://github.com/chilin11/HivisionID-X)。

> 本项目 fork 自 [Zeyi-Lin/HivisionIDPhotos](https://github.com/Zeyi-Lin/HivisionIDPhotos)。底层的证件照处理能力建立在上游项目和开源模型之上，感谢原作者。我主要重构了 Web 工作台、API 服务和智能构图流程。

## 30 秒跑起来

发布的镜像已经包含模型权重，同时支持 `linux/amd64` 和 `linux/arm64`，不需要装 Python，也不需要构建前端：

```bash
docker run -d \
  --name hivisionid-x \
  --restart unless-stopped \
  -p 7860:7860 \
  chilin11/hivisionid-x:latest
```

然后打开 `http://localhost:7860`。家里的 NAS 或者树莓派一类的 ARM 设备也能跑。

## 它能做什么

- **工作台**：支持拖拽、选择文件、从剪贴板粘贴，中英文界面，桌面和手机都能用。
- **抠图与换底**：默认使用 BEN2 + RetinaFace，可以换成纯色、渐变或自定义背景。
- **尺寸与输出**：内置常用尺寸，也可以自定义像素或毫米；支持 PNG / JPEG、DPI、目标 KB 和水印。
- **打印排版**：5 / 6 英寸、A4、3R、4R 排版，带裁剪线，打印后直接剪。
- **可选增强**：亮度、对比度、美白、锐化、人脸矫正和 AI 超分。

## 这次重点改了什么：构图

证件照好不好看，一大半取决于**头在画面里占多大**。我把构图逻辑重写了一遍：

1. 头部高度默认占画面的 **59%**，页面上可以在 50%–69% 之间调整；
2. 原图空间允许时，头顶留白保持在 10%–12%；
3. 不会为了让身体贴底而再次放大头部，给脖子和肩膀留出空间；
4. 调整构图滑杆时会**复用之前的抠图结果**，只重新裁剪，所以几乎是实时的。

大图也有专门处理：上传上限 40 MB，超过 2400 万像素会自动等比例缩小，并按 EXIF 信息校正方向。手机原图直接传就行。

## 当作 API 用

服务启动后打开 `/docs` 就能看到交互式接口文档。比如生成一张 295 × 413 像素的蓝底照：

```bash
curl -X POST http://localhost:7860/idphoto \
  -F "input_image=@portrait.jpg" \
  -F "height=413" \
  -F "width=295" \
  -F "head_height_fraction=0.59" \
  -F "color=438edb"
```

另外还有抠图（`/human_matting`）、换背景（`/add_background`）、打印排版（`/generate_layout_photos`）、调整文件大小（`/set_kb`）等接口，方便集成到你自己的系统里。

## 需要注意

尺寸预设主要用来选择输出大小，**并不代表已经符合每一种证件的规范**，正式使用前请再核对一遍背景、头部尺寸和文件要求。另外，原图里没拍到肩膀的话，裁剪是补不出来的。

如果这个项目帮你省了一趟照相馆，欢迎给个 Star，或者在 Issues 里告诉我哪里还不好用。

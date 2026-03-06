# Twitter/X Article Publisher

使用 Playwright 自动发布文章到 Twitter/X，支持从 Markdown 文件读取内容，自动生成封面图。

## 文件结构

```
twitter/
├── publish_article.py   # 主脚本
├── cover_image.py       # 封面图生成（Pillow）
├── article_loader.py    # Markdown / 纯文本解析
└── requirements.txt
```

## 安装

```bash
pip install -r requirements.txt
python -m playwright install chromium
```

## 使用

### 基本用法

```bash
python publish_article.py \
  --cookies cookies.json \
  --article path/to/article.md
```

### 所有参数

| 参数 | 说明 |
|------|------|
| `--cookies` | cookies JSON 文件路径（必填） |
| `--article` | Markdown 文章文件路径 |
| `--title` | 文章标题（与 `--body` 配合使用） |
| `--body` | 正文文本文件路径（与 `--title` 配合使用） |
| `--cover` | 封面图路径（不指定则自动生成） |
| `--headless` | 无头模式运行 |
| `--dry-run` | 测试模式，不实际点击发布 |

### 示例

```bash
# 从 markdown 文件发布（自动生成封面图）
python publish_article.py --cookies cookies.json --article article.md

# 指定封面图
python publish_article.py --cookies cookies.json --article article.md --cover cover.png

# 先测试（不发布）
python publish_article.py --dry-run --cookies cookies.json --article article.md

# 指定标题和正文文件
python publish_article.py --cookies cookies.json --title "Why C#?" --body body.txt
```

## 导出 Cookies

1. 安装 [EditThisCookie](https://chrome.google.com/webstore/detail/editthiscookie) 插件
2. 登录 Twitter/X
3. 点击插件 → 点击导出图标
4. 将内容保存为 `cookies.json`

> `cookies.json` 包含登录信息，请勿提交到版本控制。

## 工作原理

1. 加载 cookies，使用已登录身份打开浏览器
2. 导航到 `x.com/compose/articles`
3. 通过 `input[type="file"].set_input_files()` 直接上传封面图（绕过系统文件对话框）
4. 填写标题和正文（模拟键盘输入）
5. 点击"发布"按钮并确认

## 封面图

未指定 `--cover` 时自动生成：深色渐变背景 + 文章标题大字 + 副标签，输出 1500×600 PNG（5:2 比例）。

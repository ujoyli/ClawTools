#!/usr/bin/env python3
"""
get_img_from_hupu.py - 抓取虎扑帖子正文和图片
Usage: python3 get_img_from_hupu.py <url>
"""
import sys
import os
import re
import time
import requests
from bs4 import BeautifulSoup
import urllib3
urllib3.disable_warnings()

TMP_DIR = '/root/.openclaw/workspace/tmp'
os.makedirs(TMP_DIR, exist_ok=True)

def fetch_content(url):
    """抓取虎扑帖子内容"""
    headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    }
    
    try:
        resp = requests.get(url, headers=headers, timeout=30, verify=False)
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, 'html.parser')
        
        # 提取标题
        title = soup.title.string if soup.title else ''
        title = title.replace('- 虎扑社区', '').strip()
        
        # 提取正文 - 主楼内容
        body_text = ''
        
        # 方法1: 找主贴内容区
        main_post = soup.find('div', class_='post-content_main-post-info__qCbZu')
        if main_post:
            content_div = main_post.find('div', class_='thread-content-detail')
            if content_div:
                # 获取所有段落文本
                paragraphs = []
                for p in content_div.find_all(['p', 'div']):
                    text = p.get_text(strip=True)
                    if len(text) > 5 and not text.startswith('回复'):
                        paragraphs.append(text)
                body_text = ' '.join(paragraphs[:5])  # 最多取5段
        
        # 方法2: 如果方法1失败，直接找 thread-content-detail
        if not body_text or len(body_text) < 10:
            content_div = soup.find('div', class_='thread-content-detail')
            if content_div:
                # 排除回复区
                for reply in content_div.find_all('div', class_=lambda x: x and 'reply' in x.lower()):
                    reply.decompose()
                body_text = content_div.get_text(separator=' ', strip=True)
        
        # 清理正文
        body_text = re.sub(r'\s+', ' ', body_text).strip()[:300]  # 限制长度
        
        # 提取图片 - 多策略，过滤logo/头像
        image_url = None
        bad_patterns = ['def_', 'avatar', 'logo', 'icon', 'banner', 'nba-logo']
        
        # 策略1: 主贴内容区的图片
        if main_post:
            content_div = main_post.find('div', class_='thread-content-detail')
            if content_div:
                for img in content_div.find_all('img'):
                    src = img.get('data-origin') or img.get('data-original') or img.get('src', '')
                    if not src or not src.startswith('http'):
                        continue
                    if any(bad in src.lower() for bad in bad_patterns):
                        continue
                    # 优先大图
                    if 'w_' in src or 'h_' in src:
                        image_url = src
                        break
                    if not image_url:
                        image_url = src
        
        # 策略2: 全页找符合尺寸的图片
        if not image_url:
            for img in soup.find_all('img'):
                src = img.get('data-origin') or img.get('data-original') or img.get('src', '')
                if not src or not src.startswith('http'):
                    continue
                if any(bad in src.lower() for bad in bad_patterns):
                    continue
                # 必须有尺寸参数的大图
                if 'w_' in src and ('h_' in src or 'x-oss' in src):
                    image_url = src
                    break
        
        print(f'TITLE {title}')
        print(f'BODY {body_text}' if body_text else 'BODY [无正文]')
        print(f'IMAGE {image_url or ""}')
        
        return title, body_text, image_url
        
    except Exception as e:
        print(f'ERROR {e}', file=sys.stderr)
        return None, None, None

def download_image(url):
    """下载图片"""
    if not url:
        return None
    
    try:
        headers = {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'}
        resp = requests.get(url, headers=headers, timeout=30, verify=False)
        resp.raise_for_status()
        
        ext = url.split('.')[-1].split('?')[0][:4]
        if ext not in ['jpg', 'jpeg', 'png', 'gif', 'webp']:
            ext = 'jpg'
        filename = f'hupu_{int(time.time())}.{ext}'
        filepath = os.path.join(TMP_DIR, filename)
        
        with open(filepath, 'wb') as f:
            f.write(resp.content)
        
        if os.path.getsize(filepath) < 5000:  # 至少5KB
            os.remove(filepath)
            return None
            
        return filepath
        
    except Exception as e:
        print(f'DOWNLOAD_ERROR {e}', file=sys.stderr)
        return None

def main():
    if len(sys.argv) < 2:
        print('Usage: python3 get_img_from_hupu.py <url>', file=sys.stderr)
        sys.exit(1)
    
    url = sys.argv[1]
    
    for attempt in range(1, 6):
        print(f'[*] Attempt {attempt}/5...', file=sys.stderr)
        
        title, body, image_url = fetch_content(url)
        
        if title and image_url:
            img_path = download_image(image_url)
            if img_path:
                print(f'SAVED {img_path}')
                print(f'SRC {image_url}')
                sys.exit(0)
        
        time.sleep(2)
    
    print('[FAILED]', file=sys.stderr)
    sys.exit(1)

if __name__ == '__main__':
    main()

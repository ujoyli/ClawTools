#!/usr/bin/env python3
"""
X 评论效果追踪分析器
分析已发布回复的表现数据，找出最有效的话题和风格
"""

import json
import os
from collections import defaultdict
from datetime import datetime

LOG_FILE = "/root/.openclaw/workspace/data/x_reply_log.jsonl"
OUTPUT_FILE = "/root/.openclaw/workspace/data/x_reply_analysis.json"

def load_replies():
    """加载回复日志"""
    replies = []
    if not os.path.exists(LOG_FILE):
        print(f"日志文件不存在：{LOG_FILE}")
        return replies
    
    with open(LOG_FILE, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    replies.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    return replies

def analyze_replies(replies):
    """分析回复数据"""
    if not replies:
        return {"error": "no data"}
    
    # 基础统计
    total = len(replies)
    with_views = [r for r in replies if r.get('views')]
    with_score = [r for r in replies if r.get('score')]
    
    # 按话题分类（从 tweet_text 提取关键词）
    topic_keywords = {
        '科技': ['AI', 'Google', 'Apple', 'Tesla', '软件', '地图', 'MacBook', 'Adobe'],
        '体育': ['NFL', 'Bears', 'Vikings', 'Steelers', 'Bills', 'Raiders', 'QB', 'Bears'],
        '财经': ['USDT', 'AAVE', 'crypto', '$', 'million', '万'],
        '八卦': ['搞笑', '吐槽', '少爷', '车商', '体制内'],
        '政治': ['US', 'China', '护照', '伊拉克', 'CENTCOM'],
        '其他': []
    }
    
    topic_stats = defaultdict(lambda: {'count': 0, 'total_views': 0, 'total_score': 0})
    
    for r in replies:
        tweet_text = r.get('tweet_text', '') + ' ' + r.get('reply_text', '')
        reply_text = r.get('reply_text', '')
        
        # 分类
        assigned = False
        for topic, keywords in topic_keywords.items():
            if any(kw.lower() in tweet_text.lower() for kw in keywords if kw):
                topic_stats[topic]['count'] += 1
                topic_stats[topic]['total_views'] += r.get('views', 0)
                topic_stats[topic]['total_score'] += r.get('score', 0)
                assigned = True
                break
        
        if not assigned:
            topic_stats['其他']['count'] += 1
            topic_stats['其他']['total_views'] += r.get('views', 0)
            topic_stats['其他']['total_score'] += r.get('score', 0)
    
    # 计算平均表现
    topic_avg = {}
    for topic, stats in topic_stats.items():
        if stats['count'] > 0:
            topic_avg[topic] = {
                'count': stats['count'],
                'avg_views': round(stats['total_views'] / stats['count'], 0) if stats['total_views'] else 0,
                'avg_score': round(stats['total_score'] / stats['count'], 1) if stats['total_score'] else 0
            }
    
    # 按平均分数排序
    sorted_topics = sorted(
        topic_avg.items(),
        key=lambda x: x[1]['avg_score'],
        reverse=True
    )
    
    # 最近 10 条回复详情
    recent = replies[-10:] if len(replies) >= 10 else replies
    
    # 时间分布
    hour_dist = defaultdict(int)
    for r in replies:
        ts = r.get('ts', 0)
        if ts:
            hour = datetime.fromtimestamp(ts).hour
            hour_dist[hour] += 1
    
    return {
        'generated_at': datetime.now().isoformat(),
        'summary': {
            'total_replies': total,
            'with_views': len(with_views),
            'with_score': len(with_score),
            'avg_views': round(sum(r.get('views', 0) for r in with_views) / len(with_views), 0) if with_views else 0,
            'avg_score': round(sum(r.get('score', 0) for r in with_score) / len(with_score), 1) if with_score else 0
        },
        'topic_performance': dict(sorted_topics),
        'hour_distribution': dict(sorted(hour_dist.items())),
        'recent_replies': recent,
        'recommendations': generate_recommendations(sorted_topics, hour_dist)
    }

def generate_recommendations(sorted_topics, hour_dist):
    """生成优化建议"""
    recs = []
    
    if sorted_topics:
        best_topic = sorted_topics[0][0]
        best_score = sorted_topics[0][1]['avg_score']
        recs.append(f"✅ 最佳话题：{best_topic} (平均分 {best_score})")
    
    if sorted_topics:
        worst_topic = sorted_topics[-1][0]
        recs.append(f"⚠️ 表现较弱：{worst_topic}，建议减少此类评论")
    
    # 活跃时段
    if hour_dist:
        peak_hour = max(hour_dist.items(), key=lambda x: x[1])[0]
        recs.append(f"🕐 活跃时段：{peak_hour}:00-{peak_hour+1}:00 发布最多")
    
    return recs

def main():
    print("🔍 加载回复数据...")
    replies = load_replies()
    print(f"📊 找到 {len(replies)} 条回复")
    
    if not replies:
        print("❌ 没有数据可分析")
        return
    
    print("📈 分析中...")
    analysis = analyze_replies(replies)
    
    # 保存结果
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        json.dump(analysis, f, ensure_ascii=False, indent=2)
    
    print(f"✅ 分析完成，结果保存至：{OUTPUT_FILE}")
    
    # 打印摘要
    print("\n" + "="*50)
    print("📊 X 评论效果分析摘要")
    print("="*50)
    
    summary = analysis.get('summary', {})
    print(f"总评论数：{summary.get('total_replies', 0)}")
    print(f"有观看数据：{summary.get('with_views', 0)}")
    print(f"平均观看：{summary.get('avg_views', 0):,.0f}")
    print(f"平均分数：{summary.get('avg_score', 0):.1f}")
    
    print("\n🎯 话题表现排名:")
    for topic, stats in analysis.get('topic_performance', {}).items():
        print(f"  {topic}: {stats['count']}条 | 均分 {stats['avg_score']:.1f} | 均观看 {stats['avg_views']:,.0f}")
    
    print("\n💡 建议:")
    for rec in analysis.get('recommendations', []):
        print(f"  {rec}")

if __name__ == '__main__':
    main()

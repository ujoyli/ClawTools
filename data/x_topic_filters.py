# x_topic_filters.py - 话题过滤配置
# 政治关键词（过滤）
POLITICAL_KEYWORDS = [
    '政治', '习近平', '共产党', '中共', '特朗普', '拜登', '美国大选', '两会', '中南海', '白宫',
    '普京', '俄罗斯', '乌克兰', '以色列', '哈马斯', '伊朗', '战争', '军队', '军方', '敏感',
    '封禁', '审查', '台海', '台湾', '香港', '新疆', '西藏', '反华', '辱华'
]

# 技术关键词（优先，加分）
TECH_KEYWORDS = [
    'AI', '人工智能', 'GPT', 'Claude', '编程', '代码', '软件', '开发', '技术', '科技',
    '互联网', '创业', '产品', '算法', '机器学习', '深度学习', '区块链', 'Web3', 'SaaS', 'API',
    'GitHub', '开源', 'LLM', '模型', 'GPU', '芯片', '半导体', '编程语言', '框架', '数据库'
]

# 社会/八卦关键词（次优先，加分）
SOCIETY_KEYWORDS = [
    '社会', '热点', '新闻', '八卦', '明星', '娱乐', '电影', '音乐', '游戏', '体育',
    'NBA', '足球', '篮球', '恋爱', '情感', '职场', '生活', '搞笑', '美食', '旅行'
]

def is_political(text):
    """检查是否包含政治关键词"""
    text_lower = text.lower()
    return any(kw in text_lower for kw in POLITICAL_KEYWORDS)

def get_topic_score(text):
    """计算话题优先级分数"""
    text_lower = text.lower()
    if is_political(text):
        return -1000  # 政治内容直接过滤
    if any(kw in text_lower for kw in TECH_KEYWORDS):
        return 100   # 技术优先
    if any(kw in text_lower for kw in SOCIETY_KEYWORDS):
        return 50    # 社会次优先
    return 0
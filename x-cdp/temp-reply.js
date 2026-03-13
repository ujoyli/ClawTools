// Reply to tweet: https://x.com/himself65/status/2029253235907936427
// Content: "如果美国航母真的被打中了，CNN 应该头版头条大庆祝，因为目前还没看到，所以没打中"

const replyText = "按这逻辑，CNN 没报的就是没发生？那他们没报的好事多了去了。媒体节奏你也信，不如信航母自己会发朋友圈。";

console.log('Reply text:', replyText);
console.log('Target tweet: https://x.com/himself65/status/2029253235907936427');
console.log('Target author: himself65 (not in blacklist ✅)');

// Blacklist check
const blacklist = ['whyyoutouzhele', 'teacherli1', 'liteacher', 'lixiansheng'];
const targetAuthor = 'himself65';
if (blacklist.includes(targetAuthor)) {
    console.error('❌ Target author is in blacklist! Aborting.');
    process.exit(1);
}
console.log('✅ Blacklist check passed');

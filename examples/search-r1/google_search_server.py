import asyncio
import os
import random
import re
import urllib.parse
from typing import Dict, List

import aiohttp
import chardet


# --- Utilities ---

# 解析搜索片段，按 "..." 分割并过滤掉短片段（少于5个词）
def parse_snippet(snippet: str) -> List[str]:
    segments = snippet.split("...")
    return [s.strip() for s in segments if len(s.strip().split()) > 5]

# 清理搜索查询字符串，移除特殊字符、控制字符和多余空格
def sanitize_search_query(query: str) -> str:
    # Remove or replace special characters that might cause issues.
    # This is a basic example; you might need to add more characters or patterns.
    sanitized_query = re.sub(r"[^\w\s]", " ", query)  # Replace non-alphanumeric and non-whitespace with spaces.
    sanitized_query = re.sub(
        r"[\t\r\f\v\n]", " ", sanitized_query
    )  # replace tab, return, formfeed, vertical tab with spaces.
    sanitized_query = re.sub(
        r"\s+", " ", sanitized_query
    ).strip()  # remove duplicate spaces, and trailing/leading spaces.

    return sanitized_query

# 从搜索结果中筛选链接，只保留 HTML 页面链接（排除 PDF 等文件）
def filter_links(search_results: List[Dict]) -> List[str]:
    links = []
    for result in search_results:
        for item in result.get("items", []):
            if "mime" in item:
                continue
            ext = os.path.splitext(item["link"])[1]
            if ext in ["", ".html", ".htm", ".shtml"]:
                links.append(item["link"])
    return links

# 异步抓取单个URL的内容
async def fetch(session: aiohttp.ClientSession, url: str, semaphore: asyncio.Semaphore) -> str:
    if url == "":
        return ""
    user_agents = [
        "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P)...",
        "Mozilla/5.0 AppleWebKit/537.36...",
        "Mozilla/5.0 (compatible; Googlebot/2.1; +https://www.google.com/bot.html)",
    ]
    headers = {"User-Agent": random.choice(user_agents)}

    async with semaphore:
        try:
            async with session.get(url, headers=headers) as response:
                raw = await response.read()
                detected = chardet.detect(raw)
                encoding = detected["encoding"] or "utf-8"
                return raw.decode(encoding, errors="ignore")
        except (aiohttp.ClientError, asyncio.TimeoutError):
            return ""

# 并发抓取多个URL
async def fetch_all(urls: List[str], limit: int = 8) -> List[str]:
    semaphore = asyncio.Semaphore(limit)
    timeout = aiohttp.ClientTimeout(total=5)
    connector = aiohttp.TCPConnector(limit_per_host=limit, force_close=True)

    async with aiohttp.ClientSession(timeout=timeout, connector=connector) as session:
        tasks = [fetch(session, url, semaphore) for url in urls]
        return await asyncio.gather(*tasks)

# 从完整网页内容中提取与搜索片段相关的段落作为上下文
def collect_context(snippet: str, doc: str) -> str:
    snippets = parse_snippet(snippet)
    ctx_paras = []

    for s in snippets:
        pos = doc.replace("\n", " ").find(s)
        if pos == -1:
            continue
        sta = pos
        while sta > 0 and doc[sta] != "\n":
            sta -= 1
        end = pos + len(s)
        while end < len(doc) and doc[end] != "\n":
            end += 1
        para = doc[sta:end].strip()
        if para not in ctx_paras:
            ctx_paras.append(para)

    return "\n".join(ctx_paras)

#snippet_only=True: 只返回搜索片段
async def google_search(api_key, query, top_k=5, timeout: int = 60, proxy=None, snippet_only=False) -> List[Dict]:
    timeout_obj = aiohttp.ClientTimeout(total=timeout)
    # 用 urllib.parse.quote 对搜索词进行编码，防止空格或特殊字符出错
    query_str = str(query) if query is not None else ""
    query_encoded = urllib.parse.quote(query_str)

    # 配置glm搜索服务
    provider = "serper"
    base_url = "https://reader.psmoe.com/glm/s/"
    url = f"{base_url}?q={query_encoded}&provider={provider}&num={top_k}"

    session_kwargs = {}
    if proxy:
        session_kwargs["proxy"] = proxy
    async with aiohttp.ClientSession(**session_kwargs) as session:
        async with session.get(
            url,
            headers={
                "Authorization": "anonymous"
            },
            timeout=timeout_obj,
            ssl=False
        ) as resp:
            resp.raise_for_status()
            text = await resp.text()

            # 解析纯文本格式的返回结果并封装在item中
            items = []
            # 按\n\n分割每个结果项
            result_blocks = text.strip().split("\n\n")
            for block in result_blocks:
                if not block.strip():
                    continue
                lines = block.split("\n")
                item = {}
                for line in lines:
                    if "Title:" in line:
                        item["title"] = line.split("Title:", 1)[1].strip()
                    elif "URL Source:" in line:
                        item["link"] = line.split("URL Source:", 1)[1].strip()
                    elif "Description:" in line:
                        item["snippet"] = line.split("Description:", 1)[1].strip()
                if item:
                    items.append(item)

    contexts = []
    if snippet_only:
        for item in items:
            title = item.get("title", "")
            context = " ".join(parse_snippet(item.get("snippet", "")))
            if title != "" or context != "":
                title = "No title." if not title else title
                context = "No snippet available." if not context else context
                contexts.append(
                    {
                        "document": {"contents": f'"{title}"\n{context}'},
                    }
                )
    else:
        # 提取所有搜索结果的链接
        links = [item.get("link", "") for item in items if "link" in item]
        # 并发抓取所有链接的完整网页内容
        web_contents = await fetch_all(links)
        # 初始化上下文结果列表
        contexts = []
        # 遍历每个搜索结果项，同时获取索引和内容
        for i, item in enumerate(items):
            # 提取搜索结果的标题
            title = item.get("title", "")
            # 提取搜索结果的片段摘要
            snippet = item.get("snippet", "")

            # 从抓取的完整网页中提取与片段相关的段落上下文
            context = collect_context(snippet, web_contents[i])
            # 只保留有内容的结果（标题或上下文至少有一个非空）
            if title != "" or context != "":
                # 如果标题为空，设置默认标题
                title = "No title." if not title else title
                # 如果上下文为空，设置默认提示
                context = "No snippet available." if not context else context
                # 将结果构造成指定格式并添加到列表
                contexts.append(
                    {
                        "document": {"contents": f'"{title}"\n{context}'},
                    }
                )

    return contexts

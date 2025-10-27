import asyncio
import os
import random
import re
import urllib.parse
from typing import Dict, List
import ast
from openai import OpenAI

import aiohttp


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

# 抓取单个页面内容（通过远程服务）
async def fetch_page(url: str) -> str:
    """通过远程抓取服务获取页面内容（支持JS渲染和代理）"""
    max_retries = 3
    timeout = 50

    # 验证 URL
    url = url.strip()
    if not url:
        return "Format error: No URL provided"

    search_server_url = "http://127.0.0.1:9999"

    for attempt in range(max_retries):
        try:
            payload = {
                "task_id": "demo_task",
                "url": url,
                "use_proxy": True,
            }

            # 使用 aiohttp 异步请求
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{search_server_url}/fetch",
                    json=payload,
                    timeout=aiohttp.ClientTimeout(total=timeout)
                ) as resp:
                    resp.raise_for_status()
                    result_json = await resp.json()
                    result_dict = ast.literal_eval(result_json['result'])
                    response = result_dict['response']

                    if response:
                        # 过滤空行和纯星号行
                        lines = response.split('\n')
                        filtered_lines = []
                        for line in lines:
                            stripped_line = line.strip()
                            if stripped_line and not all(c == '*' for c in stripped_line):
                                filtered_lines.append(line)
                        response = '\n'.join(filtered_lines)

                    return response

        except Exception as e:
            if attempt == max_retries - 1:
                return f"[FETCH_FAILED] Failed to fetch page after {max_retries} attempts: {str(e)}"
            await asyncio.sleep(0.5)

    return "[FETCH_FAILED] Failed to fetch page."

# 使用 LLM 总结网页内容
async def _summarize_single_url(url: str, query: str) -> str:
    """使用 LLM 生成单个 URL 的内容总结"""
    try:
        # 抓取网页内容
        content = await fetch_page(url)

        # 如果抓取失败，直接返回错误信息
        if content.startswith("[FETCH_FAILED]") or content.startswith("Format error"):
            return content

        # 限制内容长度避免超出 token 限制
        limited_content = content[:30000] if len(content) > 30000 else content

        summary_prompt = f"""Please process the following webpage content and user goal to extract relevant information:

## **Webpage Content**
{limited_content}

## **User Goal**
{query}

## **Task Guidelines**
1. **Content Scanning for Rational**: Locate the **specific sections/data** directly related to the user's goal within the webpage content
2. **Key Extraction for Evidence**: Identify and extract the **most relevant information** from the content, you never miss any important information, output the **full original context** of the content as far as possible, it can be more than three paragraphs.
3. **Summary Output for Summary**: Organize into a concise paragraph with logical flow, prioritizing clarity and judge the contribution of the information to the goal.

**Final Output Format using JSON format has "rational", "evidence", "summary" feilds**
"""

        # 使用 asyncio.to_thread 包装同步的 OpenAI 调用
        def call_llm():
            client = OpenAI(
                api_key="adC6qMHni1tzmJDoA1DY8jW7uTT6BO7Ss5ownNewC51V2CvRp38d9cVfUEmcffXY",
                base_url="https://api.zhipuai-infra.cn/v1"
            )

            messages = [{"role": "user", "content": summary_prompt}]

            response = client.chat.completions.create(
                messages=messages,
                model="public-glm-4-plus",
                temperature=0.3,
                stream=False,
                max_tokens=1024
            )

            return response.choices[0].message.content.strip()

        # 在线程池中执行同步调用
        summary = await asyncio.to_thread(call_llm)

        return summary

    except Exception as e:
        return f"[SUMMARY_FAILED] Error summarizing {url}: {str(e)}"


# 异步抓取并总结单个URL的内容
async def fetch(snippet: str, url: str, semaphore: asyncio.Semaphore) -> str:
    """抓取网页并使用 LLM 生成与 snippet 相关的总结"""
    async with semaphore:
        try:
            # 调用 LLM 总结函数，使用 snippet 作为查询目标
            summary = await _summarize_single_url(url, snippet)
            return summary
        except Exception as e:
            return f"[FETCH_ERROR] Error processing {url}: {str(e)}"

# 并发抓取并总结多个URL
async def fetch_all(url_snippet_pairs: List[tuple[str, str]], limit: int = 8, proxy=None) -> List[str]:
    """
    并发抓取多个 URL 并使用 LLM 生成总结

    Args:
        url_snippet_pairs: List of (url, snippet) tuples
        limit: 并发限制
        proxy: 代理设置（注：新方案中由远程服务器处理代理）

    Returns:
        List of summaries/contents
    """
    semaphore = asyncio.Semaphore(limit)

    # 为每个 (url, snippet) 对创建任务
    tasks = [fetch(snippet, url, semaphore) for url, snippet in url_snippet_pairs]
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

    # 配置glm搜索服务（国内服务，无需代理）
    provider = "serper"
    base_url = "https://reader.psmoe.com/glm/s/"
    url = f"{base_url}?q={query_encoded}&provider={provider}&num={top_k}"

    async with aiohttp.ClientSession() as session:
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
            snippet = item.get("snippet", "")
            context = " ".join(parse_snippet(snippet))

            if title != "" or context != "":
                title = "No title." if not title else title
                # 改进：区分是否有原始 snippet
                if not context:
                    if not snippet:
                        context = "[NO_SNIPPET] Search result has no description"
                    else:
                        context = f"[FILTERED_OUT] Snippet too short: {snippet[:80]}"
                contexts.append(
                    {
                        "document": {"contents": f'"{title}"\n{context}'},
                    }
                )
    else:
        # 构造 (url, snippet) 对用于并发抓取和总结
        url_snippet_pairs = [
            (item.get("link", ""), item.get("snippet", ""))
            for item in items if "link" in item
        ]

        # 并发抓取所有链接并使用 LLM 生成总结
        # 注：新方案中通过远程服务器处理 JS 渲染和代理，proxy 参数暂时保留
        web_contents = await fetch_all(url_snippet_pairs, limit=8, proxy=proxy)

        # 初始化上下文结果列表
        contexts = []

        # 遍历每个搜索结果项，同时获取索引和内容
        for i, item in enumerate(items):
            # 提取搜索结果的标题
            title = item.get("title", "")
            # 提取搜索结果的片段摘要
            snippet = item.get("snippet", "")
            link = item.get("link", "")

            # 获取 LLM 总结的内容（不再需要 collect_context）
            context = web_contents[i] if i < len(web_contents) else ""

            # 只保留有内容的结果（标题或上下文至少有一个非空）
            if title != "" or context != "":
                # 如果标题为空，设置默认标题
                title = "No title." if not title else title

                # 如果上下文为空，提供诊断信息
                if not context:
                    context = "[ERROR] No summary generated"
                # 检查是否是错误信息
                elif context.startswith("[FETCH_FAILED]") or context.startswith("[SUMMARY_FAILED]") or context.startswith("[FETCH_ERROR]"):
                    # 保持错误信息原样，添加 URL 方便调试
                    if "URL:" not in context:
                        context = f"{context}\nURL: {link}"

                # 将结果构造成指定格式并添加到列表
                contexts.append(
                    {
                        "document": {"contents": f'"{title}"\n{context}'},
                    }
                )

    return contexts

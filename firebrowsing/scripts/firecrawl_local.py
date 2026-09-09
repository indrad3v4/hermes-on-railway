#!/usr/bin/env python3
"""
firecrawl_local.py — Local Firecrawl-compatible scraper using browser_exec + CDP.

Implements Firecrawl's best practices locally:
- scrape: markdown/html/screenshot extraction with wait strategies
- interact: AI-style interaction via code execution on page
- search: web search via browser_exec navigation
- crawl: recursive crawl with URL discovery
- map: site map discovery

All operations use local Chromium CDP (127.0.0.1:9222) via browser_exec.
No API keys, no credits, 100% free.
"""
from __future__ import annotations

import json
import time
import urllib.parse
from typing import Any

class ScrapeResult:
    def __init__(self, success: bool, data: dict | None = None, error: str | None = None):
        self.success = success
        self.data = data or {}
        self.error = error

    def to_dict(self) -> dict:
        return {"success": self.success, "data": self.data, "error": self.error}


class FirecrawlLocal:
    """Firecrawl-compatible client backed by local browser_exec CDP."""

    def __init__(self, cdp_url: str = "http://127.0.0.1:9222"):
        self.cdp_url = cdp_url
        self._session_id = None

    def _js(self, code: str) -> Any:
        """Execute JS in browser_exec context."""
        return js(code)

    def _goto(self, url: str) -> None:
        """Navigate to URL."""
        goto_url(url)
        wait_for_load()

    def _wait_for(self, selector: str, timeout: float = 20.0) -> bool:
        """Wait for selector to appear."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                if bool(self._js(f"document.querySelector('{selector}')")):
                    return True
            except Exception:
                pass
            time.sleep(0.5)
        return False

    def _extract_markdown(self) -> str:
        """Extract page as clean markdown-like text using Firecrawl patterns."""
        return self._js("""(() => {
            const selectors = [
                'script', 'style', 'nav', 'footer', 'header',
                '[role=\"navigation\"]', '[role=\"banner\"]', '[role=\"contentinfo\"]',
                '.ad', '.ads', '.advertisement', '.cookie-banner',
                '#cookie-banner', '.popup', '.modal'
            ];
            const clone = document.body.cloneNode(true);
            selectors.forEach(sel => clone.querySelectorAll(sel).forEach(el => el.remove()));
            function textify(node) {
                if (node.nodeType === Node.TEXT_NODE) return node.textContent;
                if (node.nodeType !== Node.ELEMENT_NODE) return '';
                const tag = node.tagName.toLowerCase();
                const children = Array.from(node.childNodes).map(textify).join('');
                if (['h1','h2','h3','h4','h5','h6'].includes(tag)) return '\\n## ' + children.trim() + '\\n\\n';
                if (tag === 'p') return '\\n' + children.trim() + '\\n\\n';
                if (tag === 'li') return '- ' + children.trim() + '\\n';
                if (tag === 'code') return '`' + children.trim() + '`';
                if (tag === 'pre') return '\\n```\\n' + children.trim() + '\\n```\\n\\n';
                if (tag === 'a') {
                    const href = node.getAttribute('href') || '';
                    const text = children.trim();
                    if (href && text) return text + ' (' + href + ')';
                    return text;
                }
                if (['div','section','article','main'].includes(tag)) return children + '\\n\\n';
                return children;
            }
            const body = document.body;
            if (!body) return '';
            const text = textify(body);
            return text.replace(/\\n{3,}/g, '\\n\\n').trim();
        })()""")

    def _extract_metadata(self) -> dict:
        """Extract page metadata Firecrawl-style."""
        return self._js("""(() => {
            const getMeta = (prop) => {
                const el = document.querySelector(`meta[property="${prop}"]`) ||
                          document.querySelector(`meta[name="${prop}"]`);
                return el ? el.getAttribute('content') : null;
            };
            return {
                title: document.title,
                description: getMeta('description') || getMeta('og:description'),
                language: document.documentElement.lang || null,
                canonical: document.querySelector('link[rel="canonical"]')?.href || null,
                robots: document.querySelector('meta[name="robots"]')?.content || null,
            };
        })()""")

    def scrape(self, url: str, formats: list[str] | None = None, only_main_content: bool = True, schema: dict | None = None) -> ScrapeResult:
        """Scrape URL — Firecrawl-compatible API."""
        formats = formats or ["markdown"]
        try:
            self._goto(url)
            self._wait_for("body", timeout=10)
            time.sleep(0.5)
            metadata = self._extract_metadata()
            data: dict[str, Any] = {"metadata": metadata}
            if "markdown" in formats:
                data["markdown"] = self._extract_markdown() if only_main_content else self._js("document.body.innerText")
            if "html" in formats:
                data["html"] = self._js("document.documentElement.outerHTML")
            if "screenshot" in formats:
                data["screenshot"] = capture_screenshot()
            if schema and "json" in formats:
                json_str = self._js("(() => {" + f"const schema = {json.dumps(schema)};" + "const result = {};" + "for (const [key, sel] of Object.entries(schema.properties || schema)) {" + "const el = document.querySelector(sel);" + "result[key] = el ? el.textContent.trim() : null;" + "}" + "return JSON.stringify(result);" + "})()")
                data["json"] = json.loads(json_str) if json_str else None
            return ScrapeResult(success=True, data=data)
        except Exception as e:
            return ScrapeResult(success=False, error=str(e))

    def interact(self, url: str, prompt: str, code: str | None = None) -> ScrapeResult:
        """Interact with page — Firecrawl-compatible API."""
        try:
            self._goto(url)
            self._wait_for("body", timeout=10)
            if code:
                output = self._js(f"(() => {code})()")
                return ScrapeResult(success=True, data={"output": str(output)})
            prompt_lower = prompt.lower()
            if "click" in prompt_lower:
                clicked = self._js(f"""(() => {{
                    const keywords = {json.dumps(prompt.lower().replace('click', '').strip())};
                    const elements = [...document.querySelectorAll('a, button, [role=\"button\"], input[type=\"submit\"]')];
                    const match = elements.find(el => el.textContent.toLowerCase().includes(keywords));
                    if (match) {{ match.click(); return 'clicked: ' + match.textContent.trim(); }}
                    return null;
                }})()""")
                if clicked:
                    time.sleep(1)
                    return ScrapeResult(success=True, data={"output": clicked})
            if "fill" in prompt_lower or "type" in prompt_lower:
                return ScrapeResult(success=True, data={"output": "use fill_input(selector, text) directly"})
            return ScrapeResult(success=False, error="prompt-based interact requires explicit code")
        except Exception as e:
            return ScrapeResult(success=False, error=str(e))

    def search(self, query: str, limit: int = 5) -> ScrapeResult:
        """Web search via browser_exec — navigates to search engine."""
        try:
            url = f"https://html.duckduckgo.com/html/?q={urllib.parse.quote(query)}"
            self._goto(url)
            time.sleep(1)
            results = self._js("""(() => {
                const items = [...document.querySelectorAll('.result')].slice(0, """ + str(limit) + """);
                return items.map(r => {
                    const title = r.querySelector('.result__title a')?.textContent.trim();
                    const href = r.querySelector('.result__url')?.href || r.querySelector('.result__title a')?.href;
                    const snippet = r.querySelector('.result__snippet')?.textContent.trim();
                    return {title, url: href, description: snippet};
                }).filter(r => r.title);
            })()""")
            return ScrapeResult(success=True, data={"web": results})
        except Exception as e:
            return ScrapeResult(success=False, error=str(e))

    def crawl(self, url: str, limit: int = 50) -> ScrapeResult:
        """Crawl site — discover URLs and scrape them."""
        try:
            map_result = self.map(url, limit=limit)
            if not map_result.success:
                return map_result
            urls = map_result.data.get("urls", [])[:limit]
            pages = []
            for page_url in urls:
                try:
                    scrape = self.scrape(page_url, formats=["markdown"])
                    if scrape.success:
                        pages.append({"url": page_url, "markdown": scrape.data.get("markdown", "")[:2000], "metadata": scrape.data.get("metadata", {})})
                except Exception:
                    continue
            return ScrapeResult(success=True, data={"pages": pages, "total": len(pages)})
        except Exception as e:
            return ScrapeResult(success=False, error=str(e))

    def map(self, url: str, limit: int = 500) -> ScrapeResult:
        """Discover all URLs on a site."""
        try:
            self._goto(url)
            time.sleep(1)
            urls = self._js(f"""(() => {{
                const base = new URL('{url}');
                const seen = new Set();
                const out = [];
                for (const a of document.querySelectorAll('a[href]')) {{
                    try {{
                        const href = a.getAttribute('href');
                        const abs = new URL(href, base).href.split('#')[0];
                        if (abs.startsWith(base.origin) && !seen.has(abs)) {{
                            seen.add(abs);
                            out.push(abs);
                        }}
                    }} catch(e) {{}}
                }}
                return out.slice(0, {limit});
            }})()""")
            return ScrapeResult(success=True, data={"urls": urls})
        except Exception as e:
            return ScrapeResult(success=False, error=str(e))


class Firecrawl:
    """Drop-in Firecrawl SDK replacement using local CDP."""

    def __init__(self, api_key: str | None = None, base_url: str | None = None):
        self.client = FirecrawlLocal()

    def scrape(self, url: str, **kwargs) -> Any:
        result = self.client.scrape(url, **kwargs)
        return type("ScrapeResponse", (), {"success": result.success, "data": type("Data", (), result.data)(), "error": result.error, "metadata": result.data.get("metadata", {})})()

    def interact(self, url: str, **kwargs) -> Any:
        result = self.client.interact(url, **kwargs)
        return type("InteractResponse", (), {"success": result.success, "output": result.data.get("output"), "error": result.error})()

    def search(self, query: str, **kwargs) -> Any:
        result = self.client.search(query, **kwargs)
        return type("SearchResponse", (), {"data": type("Data", (), {"web": result.data.get("web", [])})(), "success": result.success})()

    def crawl(self, url: str, **kwargs) -> Any:
        result = self.client.crawl(url, **kwargs)
        return type("CrawlResponse", (), {"data": type("Data", (), {"pages": result.data.get("pages", [])})(), "success": result.success})()

    def map(self, url: str, **kwargs) -> Any:
        result = self.client.map(url, **kwargs)
        return type("MapResponse", (), {"data": type("Data", (), {"urls": result.data.get("urls", [])})(), "success": result.success})()


def main():
    import sys
    import argparse
    parser = argparse.ArgumentParser(description="Local Firecrawl-compatible scraper")
    parser.add_argument("action", choices=["scrape", "interact", "search", "crawl", "map"])
    parser.add_argument("target", help="URL or query")
    parser.add_argument("--formats", default="markdown", help="Comma-separated formats")
    parser.add_argument("--limit", type=int, default=5)
    parser.add_argument("--code", default=None)
    parser.add_argument("--prompt", default=None)
    args = parser.parse_args()
    fc = FirecrawlLocal()
    if args.action == "scrape":
        result = fc.scrape(args.target, formats=args.formats.split(","))
    elif args.action == "interact":
        result = fc.interact(args.target, prompt=args.prompt or "", code=args.code)
    elif args.action == "search":
        result = fc.search(args.target, limit=args.limit)
    elif args.action == "crawl":
        result = fc.crawl(args.target, limit=args.limit)
    elif args.action == "map":
        result = fc.map(args.target, limit=args.limit)
    else:
        result = ScrapeResult(success=False, error="unknown action")
    print(json.dumps(result.to_dict(), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

"""browser_helpers.py — Firecrawl-style extraction layer ON TOP OF browser_exec.

Every helper runs in the browser_exec harness and uses the pre-imported
browser_exec primitives: new_tab, goto_url, wait_for_load, wait_for_element,
js, capture_screenshot, click_at_xy, type_text, fill_input, press_key, scroll.

Patterns borrowed from Firecrawl:
- clean markdown extraction with unwanted-element removal
- metadata extraction (title, description, canonical, robots)
- structured extraction via schema/property map
- selector-based stable interaction
- search-engine extraction via DuckDuckGo HTML
- site mapping via anchor-href collection
"""
from __future__ import annotations

import time
import json
import urllib.parse


def extract_markdown(only_main_content: bool = True) -> str:
    """Extract page as clean markdown-like text.

    Removes nav/footer/ads/scripts, preserves headings/links/code structure.
    """
    code = """(() => {
        const remove = [
            'script','style','nav','footer','header',
            '[role="navigation"]','[role="banner"]','[role="contentinfo"]',
            '.ad','.ads','.advertisement','.cookie-banner','#cookie-banner',
            '.popup','.modal','noscript'
        ];
        const clone = document.body.cloneNode(true);
        remove.forEach(sel => clone.querySelectorAll(sel).forEach(el => el.remove()));

        function textify(node) {
            if (node.nodeType === Node.TEXT_NODE) return node.textContent || '';
            if (node.nodeType !== Node.ELEMENT_NODE) return '';
            const tag = node.tagName.toLowerCase();
            const children = Array.from(node.childNodes).map(textify).join('');
            if (/^h[1-6]$/.test(tag)) return '\\n## ' + children.trim() + '\\n\\n';
            if (tag === 'p') return '\\n' + children.trim() + '\\n\\n';
            if (tag === 'li') return '- ' + children.trim() + '\\n';
            if (tag === 'code') return '`' + children.trim() + '`';
            if (tag === 'pre') return '\\n```\\n' + children.trim() + '\\n```\\n\\n';
            if (tag === 'a') {
                const href = node.getAttribute('href') || '';
                const text = children.trim();
                return (href && text) ? text + ' (' + href + ')' : text;
            }
            if (['div','section','article','main','aside'].includes(tag)) {
                return children + '\\n\\n';
            }
            return children;
        }
        const text = textify(document.body);
        return text.replace(/\\n{3,}/g, '\\n\\n').trim();
    })()"""
    try:
        return js(code) or ""
    except Exception:
        return ""


def extract_metadata() -> dict:
    """Extract page metadata Firecrawl-style."""
    code = """(() => {
        const getMeta = (prop) => {
            const el = document.querySelector('meta[property="' + prop + '"]') ||
                      document.querySelector('meta[name="' + prop + '"]');
            return el ? el.getAttribute('content') : null;
        };
        return {
            title: document.title,
            description: getMeta('description') || getMeta('og:description'),
            language: document.documentElement.lang || null,
            canonical: document.querySelector('link[rel="canonical"]')?.href || null,
            robots: document.querySelector('meta[name="robots"]')?.content || null,
        };
    })()"""
    try:
        return js(code) or {}
    except Exception:
        return {}


def extract_structured(schema: dict) -> dict | None:
    """Structured extraction using a selector-based schema.

    Schema format: {"field_name": "css selector", ...}
    """
    code = (
        "(() => {"
        f"const schema = {json.dumps(schema)};"
        "const result = {};"
        "for (const [key, sel] of Object.entries(schema)) {"
        "const el = document.querySelector(sel);"
        "result[key] = el ? el.textContent.trim() : null;"
        "}"
        "return JSON.stringify(result);"
        "})()"
    )
    try:
        raw = js(code)
        return json.loads(raw) if raw else None
    except Exception:
        return None


def search_duckduckgo(query: str, limit: int = 5) -> list[dict]:
    """Web search — default backend dispatch.

    Priority: if SEARXNG_URL is set, search via self-hosted SearXNG. Otherwise
    DuckDuckGo HTML with automatic Bing fallback when DDG serves a bot-captcha.
    """
    import os
    if os.environ.get("SEARXNG_URL"):
        r = search_searxng(query, limit=limit)
        if r:
            return r
    url = f"https://html.duckduckgo.com/html/?q={urllib.parse.quote(query)}"
    try:
        goto_url(url)
        wait_for_load()
        time.sleep(0.8)
        code = (
            "(() => {"
            f"const items = [...document.querySelectorAll('.result')].slice(0, {limit});"
            "return items.map(r => {"
            "const title = r.querySelector('.result__title a')?.textContent.trim();"
            "const href = r.querySelector('.result__url')?.href || r.querySelector('.result__title a')?.href;"
            "const snippet = r.querySelector('.result__snippet')?.textContent.trim();"
            "return {title, url: href, description: snippet};"
            "}).filter(r => r.title);"
            "})()"
        )
        results = js(code) or []
        if results:
            return results
        body = (js("document.body ? document.body.innerText : ''") or "")
        challenged = len(body) < 600 and (
            "challenge" in body.lower() or "duck" in body.lower() or "captcha" in body.lower()
        )
        if challenged:
            return search_bing(query, limit=limit)
        return []
    except Exception:
        try:
            return search_bing(query, limit=limit)
        except Exception:
            return []


def search_bing(query: str, limit: int = 5) -> list[dict]:
    """Web search via Bing HTML — fallback for DDG bot-walls."""
    url = f"https://www.bing.com/search?q={urllib.parse.quote(query)}"
    goto_url(url)
    wait_for_load()
    time.sleep(1.2)
    code = (
        "(() => {"
        f"const items = [...document.querySelectorAll('li.b_algo')].slice(0, {limit});"
        "return items.map(li => {"
        "const a = li.querySelector('h2 a') || li.querySelector('a');"
        "const p = li.querySelector('.b_caption p, p');"
        "return {title: a?.textContent.trim(), url: a?.href, description: (p?.textContent.trim()||'').slice(0,200)};"
        "}).filter(r => r.title && r.url);"
        "})()"
    )
    return js(code) or []


def search_searxng(query: str, limit: int = 5, searxng_url: str | None = None) -> list[dict]:
    """Web search via a self-hosted SearXNG JSON API."""
    import os, urllib.request
    base = searxng_url or os.environ.get("SEARXNG_URL", "")
    if not base:
        return []
    base = base.rstrip("/")
    url = f"{base}/search?q={urllib.parse.quote(query)}&format=json"
    try:
        with urllib.request.urlopen(url, timeout=15) as r:
            data = json.loads(r.read().decode())
        out = []
        for item in (data.get("results") or [])[:limit]:
            title = item.get("title") or ""
            link = item.get("url") or ""
            snippet = item.get("content") or ""
            if title and link:
                out.append({"title": title, "url": link, "description": snippet})
        return out
    except Exception:
        return []


def map_site(url: str, limit: int = 500) -> list[str]:
    """Discover URLs on a site by scanning anchor hrefs."""
    try:
        goto_url(url)
        wait_for_load()
        time.sleep(0.5)
        code = (
            "(() => {"
            f"const base = new URL('{url}');"
            "const seen = new Set();"
            "const out = [];"
            "for (const a of document.querySelectorAll('a[href]')) {"
            "try {"
            "const href = a.getAttribute('href');"
            "const abs = new URL(href, base).href.split('#')[0];"
            "if (abs.startsWith(base.origin) && !seen.has(abs)) {"
            "seen.add(abs);"
            "out.push(abs);"
            "}"
            "} catch(e) {}"
            "}"
            "return out.slice(0, " + str(limit) + ");"
            "})()"
        )
        return js(code) or []
    except Exception:
        return []


def crawl_site(url: str, limit: int = 50) -> list[dict]:
    """Crawl site: map URLs then scrape each."""
    urls = map_site(url, limit=limit)
    pages = []
    for page_url in urls:
        try:
            page_data = scrape_url(page_url)
            if page_data:
                pages.append(page_data)
        except Exception:
            continue
    return pages


def scrape_url(url: str, formats: list[str] | None = None) -> dict | None:
    """Scrape one URL — returns metadata + requested formats."""
    if formats is None:
        formats = ["markdown"]
    try:
        goto_url(url)
        wait_for_load()
        time.sleep(0.5)
        result = {"url": url, "metadata": extract_metadata()}
        if "markdown" in formats:
            result["markdown"] = extract_markdown()
        if "html" in formats:
            result["html"] = js("document.documentElement.outerHTML") or ""
        if "screenshot" in formats:
            result["screenshot"] = capture_screenshot()
        return result
    except Exception:
        return None


def click_by_text(text_fragment: str, timeout: float = 10.0) -> bool:
    """Click element whose text contains fragment."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            el = js(
                f"(() => {{ const q = '{text_fragment}'; "
                "const els = [...document.querySelectorAll('a,button,[role=\"button\"]')]; "
                "return els.find(e => e.textContent.toLowerCase().includes(q)) || null; })()"
            )
            if el:
                bbox = js(
                    "(() => { const el = document.querySelector('a,button,[role=\"button\"]') ; "
                    "if(!el) return null; const r = el.getBoundingClientRect(); "
                    "return {x:r.x+r.width/2,y:r.y+r.height/2}; })()"
                )
                if bbox:
                    click_at_xy(bbox["x"], bbox["y"])
                    return True
        except Exception:
            pass
        time.sleep(0.5)
    return False


def scroll_page(x: int = 0, y: int = 500) -> None:
    """Scroll page by delta."""
    try:
        scroll(x, y)
    except Exception:
        pass


class LocalFirecrawl:
    """Firecrawl-compatible facade over browser_exec."""

    def scrape(self, url: str, formats: list[str] | None = None, **kwargs) -> dict:
        formats = formats or ["markdown"]
        data = scrape_url(url, formats)
        if not data:
            return {"success": False, "error": "scrape failed"}
        return {"success": True, "data": data}

    def interact(self, url: str, prompt: str, **kwargs) -> dict:
        try:
            goto_url(url)
            wait_for_load()
            if click_by_text(prompt.replace("click", "").strip()):
                return {"success": True, "output": f"clicked: {prompt}"}
            return {"success": False, "error": "no matching element"}
        except Exception as e:
            return {"success": False, "error": str(e)}

    def search(self, query: str, limit: int = 5) -> dict:
        results = search_duckduckgo(query, limit=limit)
        return {"success": True, "data": {"web": results}}

    def map(self, url: str, limit: int = 500) -> dict:
        urls = map_site(url, limit=limit)
        return {"success": True, "data": {"urls": urls}}

    def crawl(self, url: str, limit: int = 50) -> dict:
        pages = crawl_site(url, limit=limit)
        return {"success": True, "data": {"pages": pages, "total": len(pages)}}

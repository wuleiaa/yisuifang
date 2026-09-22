#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
SQL 语法校验工具
使用 PostgreSQL 官方解析器（libpg_query / pglast）逐条解析 SQL 文件，
在本地提前发现语法错误，避免把问题带到部署阶段。

用法:
    python tools/sql_lint.py db/migration/V1__init_schema.sql
"""
import io
import os
import re
import sys

# Windows 控制台默认 GBK，强制 UTF-8 输出避免中文乱码
try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:  # noqa: BLE001
    pass

try:
    from pglast import parse_sql
    from pglast.parser import ParseError
except ImportError:
    print("缺少依赖，请先执行: python -m pip install pglast")
    sys.exit(2)


def mask_dollar_blocks(sql: str):
    """把 $$ ... $$ 与 $tag$ ... $tag$ 的内容替换为等长空白，避免误报。

    返回 (掩码后的文本, 被替换的块列表)。保持字符数不变，以便行号对齐。
    """
    blocks = []
    out = []
    i = 0
    n = len(sql)
    while i < n:
        if sql[i] == "$":
            j = sql.find("$", i + 1)
            if j != -1 and all(c.isalnum() or c == "_" for c in sql[i + 1:j]):
                tag = sql[i:j + 1]
                end = sql.find(tag, j + 1)
                if end != -1:
                    body = sql[j + 1:end]
                    blocks.append(body)
                    out.append(tag)
                    out.append("\n" * body.count("\n"))
                    out.append(" " * (len(body) - body.count("\n")))
                    out.append(tag)
                    i = end + len(tag)
                    continue
        out.append(sql[i])
        i += 1
    return "".join(out), blocks


def line_of(sql: str, offset: int) -> int:
    return sql.count("\n", 0, offset) + 1


SQL_HEAD = re.compile(
    r"^\s*(CREATE|ALTER|DROP|INSERT|UPDATE|DELETE|SELECT|GRANT|REVOKE|COMMENT)\b",
    re.IGNORECASE,
)


def extract_dynamic_sql(block: str):
    """从 plpgsql 过程体中抽取 EXECUTE format('...') 里的 SQL 模板并还原。

    这一类动态 SQL 才是真正会在运行时执行的语句，必须单独校验。
    """
    found = []
    # 匹配单引号字符串（SQL 中用 '' 转义单引号）
    for m in re.finditer(r"'((?:[^']|'')*)'", block):
        body = m.group(1).replace("''", "'")
        if not SQL_HEAD.match(body):
            continue
        restored = body
        restored = restored.replace("%I", "dummy_ident")
        restored = restored.replace("%L", "'dummy'")
        restored = re.sub(r"%s", "dummy_ident", restored)
        found.append((restored, m.start(1)))
    return found


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2

    path = sys.argv[1]
    if not os.path.isfile(path):
        print(f"文件不存在: {path}")
        return 2

    with io.open(path, "r", encoding="utf-8") as f:
        raw = f.read()

    print(f"文件: {path}")
    print(f"大小: {len(raw)} 字符 / {raw.count(chr(10)) + 1} 行")

    total_statements = 0
    errors = []

    # 分两遍：先校验外层语句，再单独校验 plpgsql 过程体
    stripped, blocks = mask_dollar_blocks(raw)
    print(f"检测到 {len(blocks)} 个 $$ 代码块（已单独校验）")

    # --- 第一遍：主脚本（不含 $$ 过程体） ---
    for pass_name, text in (("主脚本", stripped),):
        try:
            stmts = parse_sql(text)
            total_statements += len(stmts)
        except ParseError as e:
            # 定位到具体行
            off = getattr(e, "location", None)
            if off is None:
                msg = str(e)
                off = 0
                digits = "".join(ch for ch in msg if ch.isdigit())
                if digits:
                    off = int(digits)
            errors.append((pass_name, line_of(text, off), str(e)))
        except Exception as e:  # noqa: BLE001
            errors.append((pass_name, 0, f"{type(e).__name__}: {e}"))

    # --- 第二遍：plpgsql 过程体中的动态 SQL ---
    dyn_count = 0
    for i, b in enumerate(blocks):
        for sql_text, _off in extract_dynamic_sql(b):
            dyn_count += 1
            try:
                stmts = parse_sql(sql_text)
                total_statements += len(stmts)
            except ParseError as e:
                errors.append((f"动态SQL#{i + 1}", 0, f"{e} | 语句: {sql_text[:90]}"))
            except Exception as e:  # noqa: BLE001
                errors.append((f"动态SQL#{i + 1}", 0,
                               f"{type(e).__name__}: {e} | 语句: {sql_text[:90]}"))
    print(f"抽取并校验 {dyn_count} 条过程体内的动态 SQL")

    if errors:
        print(f"\n[失败] 发现 {len(errors)} 处语法错误：")
        for name, line, msg in errors:
            print(f"  - [{name}] 第 {line} 行: {msg}")
        return 1

    print(f"\n[通过] 共解析 {total_statements} 条语句，未发现语法错误。")
    return 0


if __name__ == "__main__":
    sys.exit(main())

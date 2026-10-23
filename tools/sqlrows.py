"""Reads rows of one table out of a MySQL dump (the cmangos TBC world database) without a database."""
import re


def _values(s, i):
    """Parses '(a,'b',3),(...)' starting at s[i]; yields tuples."""
    n = len(s)
    while i < n:
        while i < n and s[i] in ' ,\n\r\t':
            i += 1
        if i >= n or s[i] != '(':
            return
        i += 1
        row, cur, inq = [], [], False
        while i < n:
            c = s[i]
            if inq:
                if c == '\\':
                    cur.append(s[i + 1]); i += 2; continue
                if c == "'":
                    if i + 1 < n and s[i + 1] == "'":
                        cur.append("'"); i += 2; continue
                    inq = False; i += 1; continue
                cur.append(c); i += 1; continue
            if c == "'":
                inq = True; i += 1; continue
            if c == ',':
                row.append(''.join(cur)); cur = []; i += 1; continue
            if c == ')':
                row.append(''.join(cur)); i += 1
                yield row
                break
            cur.append(c); i += 1


def table(path, name):
    """Returns (columns, rows) for `name`; values are strings."""
    sql = open(path, encoding='utf-8', errors='replace').read()
    m = re.search(r'CREATE TABLE `%s` \((.*?)\n\) ENGINE' % re.escape(name), sql, re.S)
    cols = re.findall(r'^\s+`([^`]+)`', m.group(1), re.M) if m else []
    rows = []
    for mm in re.finditer(r'INSERT INTO `%s`(?: \([^)]*\))? VALUES ' % re.escape(name), sql):
        for r in _values(sql, mm.end()):
            rows.append(r)
    return cols, rows

# Patra Architecture

## File Format

```
.patra file layout:

Offset    Size     Content
0         4        Magic: "PTRA"
4         4        Version: 1
8         8        Page count
16        8        Free list head (page number, 0 = none)
24        8        Table count
32        32       Reserved
64        4032     Table directory (up to 63 tables × 64 bytes each)
4096      4096     Page 1 (data or B-tree node)
8192      4096     Page 2
...
```

## Page Layout

Each page is 4KB (4096 bytes):

```
B-tree node page:
  [0-1]    Page type (1=leaf, 2=internal)
  [2-3]    Key count
  [4-7]    Parent page number
  [8+]     Keys and child pointers (internal) or keys and row data (leaf)

Data page (JSON Lines mode):
  [0-1]    Page type (3=jsonl)
  [2-3]    Entry count
  [4+]     Newline-delimited JSON entries
```

## B-tree

Order-64 B-tree. Each node fits in one 4KB page. Keys are i64. Values are row offsets.

- Insert: walk tree, split full nodes on the way down
- Search: binary search within node, follow child pointer
- Range scan: find start key, iterate leaves
- Delete: mark as deleted, compact on page full

## SQL Pipeline

```
SQL string
  → tokenize (sql.cyr)
    → parse statement (sql.cyr)
      → CREATE → create table in directory
      → INSERT → encode row, insert into B-tree
      → SELECT → [B-tree or scan] evaluate WHERE → ORDER BY → LIMIT → project cols
      → UPDATE → find rows, modify in place
      → DELETE → find rows, mark deleted
```

## Concurrency

Advisory file locking via `flock` syscall:

```
patra_open:   open file + flock(LOCK_EX) for writes, flock(LOCK_SH) for reads
patra_close:  flock(LOCK_UN) + close
```

Multiple readers, single writer. Standard POSIX advisory locking semantics.

# n8n query sources

The SQL that lives inside the n8n Postgres nodes, kept here so it can be read,
diffed and reviewed instead of only existing in the n8n UI.

| File | Goes in |
|---|---|
| `00-diagnose-instructor-match.sql` | Nothing. Run it in the Supabase SQL editor. |
| `get-instructor-id.sql` | n8n node **get instructor id** (the Google-sheet branch) |
| `get-subject-id.sql` | n8n node **get subject id** (the Google-sheet branch) |

Both nodes take two Query Parameters, in this order:

**get instructor id**
```
{{ $json['Instructor/Professor'] || 'N/A' }}
{{ $json['Subject Taught'] }}
```

**get subject id**
```
{{ $json.instructor_id }}
{{ $json.subject_search_term }}
```

Only the Google-sheet branch uses these. The `If13`, manual-correction and
`get instructor id2/3` branches have their own copies and are untouched.

The authoritative version is whatever is in n8n; these files are a mirror.
After editing a node, paste the change back here so the two do not drift.

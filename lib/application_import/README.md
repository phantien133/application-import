# ApplicationImport

Imports tabular files (CSV now, XLSX planned) into ActiveRecord models, or into plain
attribute hashes, from a YAML definition per import. It handles reading and checking the
file, casting, validation, error policy and writing; Ruby code is only needed for what
the YAML cannot express (handler hooks, custom validators, transformers, casters,
readers).

- [Quick start](#quick-start)
- [How a run works](#how-a-run-works)
- [Running an import](#running-an-import)
- [Global settings](#global-settings)
- [Definition reference](#definition-reference): [handler](#handler), [file](#file),
  [columns](#columns), [transformers](#transformers), [mapper](#mapper),
  [validators](#validators), [output](#output), [on_error](#on_error)
- [Error codes](#error-codes)
- [Result](#result)
- [Extending](#extending)
- [Examples](#examples)

## Quick start

`config/imports/users.yml` (the file name is the import name, `:users`):

```yaml
file:
  formats: [ csv ]
columns:
  email:
    header: "Email"
    required: true
    format: email
  name:
    header: "Name"
    max_length: 100
  age:
    header: "Age"
    type: integer
    min: 0
validators:
  rows:
    - type: unique_in_file
      keys: [ email ]
      case_sensitive: false
output:
  model: User          # mode defaults to bulk (activerecord-import)
on_error: skip         # drop bad rows, keep going
```

```ruby
result = ApplicationImport.run(:users, params[:file], context: { user_id: current_user.id })
result.status       # => :completed | :completed_with_errors | :failed
result.stats        # => { total: 120, valid: 118, invalid: 2, written: 118 }
result.errors.first # => #<data ErrorEntry line=7, column="email", code=:invalid_format, ...>
```

## How a run works

Steps, in order. A file error stops the run at once; `close_reader` and
`handler.after_import` always run.

| Step | What happens |
| --- | --- |
| `validate_file` | File checker (`formats`, `name_pattern`, `max_size`), then file validators and `handler.validate_file`. |
| `open_reader` | `reader.open` (no-op for CSV). |
| `read_headers` | Headers are matched to columns (see [Headers and cells](#headers-and-cells)). |
| `process` | Every data row goes through the row pipeline below. |
| `verify` | Once, on the kept rows: verify validators, then `handler.verify`. Not run with `output.stream`. |
| `write_rows` | `handler.write(rows, writer)` with the writer of `output.mode`. Not run in a dry run. |

Row pipeline, per data row in file order:

1. extra cells check (`file.extra_cells`)
2. cast + column rules, for every column (one check)
3. each transformer (one check each)
4. mapper, `handler.map_row`, `handler.build_record`
5. row validators, then `handler.validate_row`
6. rows validators, then `handler.validate_rows`

After each check the row's errors are weighed with `on_error`. With `row_errors: first`
(default) the row stops at the first check that reports an error that is not allowed;
with `row_errors: all` every check runs. Then all the row's new errors are settled at
once: recorded in the result, and the worst action wins (`abort` > `skip` > `allow`).

Every row read stays in memory until the end (verify and write need them); skipped rows
release their record. Use `output.stream` for very large files.

## Running an import

```ruby
ApplicationImport.run(definition_or_name, file,
  filename: nil,   # needed for an IO without a path (StringIO)
  context: {},     # frozen, read-only input for the handler, transformers, validators
  runner: nil,     # a Runner subclass (class or name)
  logger: nil,     # this run only; default ApplicationImport.logger
  dry_run: false)  # every step up to the write, then stop
```

- `definition_or_name`:
  - an import name (`:users`, `"users"`; `/\A[a-z][a-z0-9_]*\z/`), loaded from
    `<config_path>/<name>.yml`;
  - a String path ending in `.yml` / `.yaml`, relative to `Rails.root`, which must stay
    inside `Rails.root`;
  - a `Pathname`, which can point anywhere;
  - a `Definition`, e.g. built inline with `ApplicationImport::Definition.build(:users, hash)`
    (global defaults applied).
- `file`:
  - a path (String or Pathname);
  - an uploaded file (responds to `tempfile` and `original_filename`);
  - a seekable IO (File, Tempfile, StringIO). Pipes and sockets are rejected because the
    file is read twice (size check, then reading).
- `dry_run: true` runs every step up to `write_rows`, then stops. Nothing is written,
  no transaction is held, `stats[:written]` is 0 and `stats[:valid]` is the number of
  rows that would be written. `handler.after_import` still runs (check
  `result.dry_run?`).

Exceptions:
- Any exception during the run (a bug in custom code, a database failure) records an
  `unexpected_error` file error and marks the result failed. Then `close_reader` and
  `after_import` run, and the exception is re-raised.
- `Errors::ConfigError` and the `Errors::Invalid*Error` classes are raised while
  loading a definition with a wrong setting. The message lists every problem found.

Definitions are parsed and frozen once, then cached by path. The cache is on unless
code reloading is on or the environment is test. Clear it with
`ApplicationImport.clear_definitions!`.

## Global settings

Optional `config/imports/_config.yml`, read lazily on first use (template:
[`example/_config.yml`](example/_config.yml)). It is either flat, or split into
environment sections: `shared` deep-merged with the current `<env>` section
(`development`, `test`, `production`). Mixing flat keys with sections is an error.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `config_path` | path | `config/imports` | Directory of `<name>.yml` definitions, relative to `Rails.root`. |
| `defaults` | mapping | `{}` | Deep-merged under every definition; definition values win. Allowed sections: `handler`, `file`, `output`, `on_error`. A section left empty in a definition (`file:` with nothing under it) keeps the defaults. |

In code (takes precedence over the file; clears the definition cache):

```ruby
ApplicationImport.configure do |config|
  config.config_path = "config/imports"
  config.defaults = { file: { max_size: 10.megabytes } }
  config.logger = Logger.new($stdout)   # default: Rails.logger
  config.cache_definitions = true       # default: !enable_reloading && !Rails.env.test?
end
ApplicationImport.reset_configuration!  # rebuild from the settings file on next access
```

## Definition reference

Top-level keys: `handler`, `file`, `columns` (required), `transformers`, `mapper`,
`validators`, `output`, `on_error`. Unknown keys are errors at every level. The full
annotated reference is [`example/users.yml`](example/users.yml).

Value types used below:
- *class*: a class name String, resolved at load. It must exist and subclass the base
  named in the row.
- *regexp*: a String holding the regexp source. It runs with a 1 s timeout per value.
- *names*: a name or a non-empty list of names.

### handler

| Key | Type | Default |
| --- | --- | --- |
| `handler` | class < `ApplicationImport::Handler` | `ApplicationImport::Handler` |

See [Handler hooks](#handler-hooks).

### file

#### Checks before reading

These are run by the file checker. A check that is not configured is skipped with a
warning. Every failing check is recorded, then the run stops.

| Key | Type | Default | Error code |
| --- | --- | --- | --- |
| `checker` | class < `ApplicationImport::FileChecker` | `FileChecker` | |
| `formats` | names from `csv`, `xlsx` (file extensions) | none (check skipped) | `invalid_format` |
| `name_pattern` | regexp, matched on the filename | none (check skipped) | `invalid_name` |
| `max_size` | integer >= 1 (bytes), or `null` for no limit | `104857600` (100 MiB) | `too_large` |

A filename containing a NUL byte is always `invalid_name`, and no other check runs on it.

#### Reading

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `format` | `csv` \| `xlsx` | the first of `formats`, else `csv` | Must be in `formats` when both are set. The reader is picked by the file's extension when it is in `formats`, else by `format`. XLSX reading is not implemented yet. |
| `reader` | class < `ApplicationImport::Readers::Base` | built-in reader | Overrides `format`. |
| `encoding` | encoding name | `UTF-8` | Content is transcoded to UTF-8. A BOM (UTF-8/16/32) in the file wins. Host aliases (`locale`, `external`, ...) and encodings Ruby cannot convert are rejected. |
| `csv` | mapping | `{}` | See below. |
| `xlsx.sheet` | index or name | `0` | Reserved for the XLSX reader. |

`file.csv`, validated options passed to `CSV.new`:

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `col_sep` | non-empty string | `","` | |
| `quote_char` | one character | `'"'` | |
| `row_sep` | non-empty string | auto | When unset, CRLF and lone CR are normalized to LF first, so mixed line endings parse. |
| `liberal_parsing` | boolean | `false` | |
| `strip` | `true` / `false` / one character | `false` | |
| `skip_lines` | regexp | none | Lines dropped before parsing (e.g. comments `'\A#'`). Only lines that start a record are tested; line numbers are kept. |
| `max_field_size` | integer >= 1 | `1048576` | A longer value, or an unclosed quote, gives `field_too_large`. |
| `passthrough` | mapping | none | Other `CSV.new` options, not validated, applied last. Options the reader manages (`headers`, `converters`, `skip_lines`, `skip_blanks`, ...) are rejected. |

`col_sep`, `quote_char` and `row_sep` must all differ.

The content is also checked while it is transcoded:
- bytes invalid in the encoding, unmappable characters and NUL bytes give
  `invalid_encoding`;
- empty or whitespace-only content gives `empty_file`.

#### Headers and cells

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `headers` | boolean | `true` | `false`: there is no header row; cells map to columns by position, in definition order. |
| `require_all_headers` | boolean | `false` | `true`: every column needs its header. Otherwise only `required` columns do; a missing optional column is nil. Missing headers give `missing_headers`. |
| `unknown_headers` | `skip` \| `keep` \| `assign` \| `reject` | `skip` | Headers matching no column. See below. |
| `assign` | `{ allow: names }` or `{ ignore: names }` | none | Only with `unknown_headers: assign`; exactly one key. |
| `extra_cells` | `warn` \| `ignore` \| `reject` | `warn` | Cells beyond the headers, kept in `row.raw`. `warn` logs the first such row and a total; `reject` gives `extra_cells` and stops. |
| `max_columns` | integer >= 1 | columns × 2 + 100 | Cells per record. More gives `too_many_cells`, and the run stops. |
| `numbers.decimal_separator` | one character, not a digit or sign | `.` | Default for decimal columns. |
| `numbers.thousands_separator` | one character, not a digit or sign | none | Default for integer and decimal columns. |

Header matching:
- A header matches a column by its `header` or one of its `aliases`, ignoring case and
  Unicode / zero-width spaces. Failing that, it matches by `header_pattern`. Names win
  over patterns.
- A header matching the patterns of several columns gives `ambiguous_headers`.
- Two headers for one column, or a repeated kept header, give `duplicate_headers`.
- For exact headers (every column, nothing else), use `require_all_headers: true` with
  `unknown_headers: reject`.

`unknown_headers`:
- `skip`: the header is ignored (logged).
- `keep`: the value is kept as a String key (`row.attributes["Note"]`). It is never
  assigned to the record; map it explicitly (mapper `rename`, handler, transformer) or
  use raw output.
- `assign`: like `keep`, and headers naming an `output.model` attribute (downcased,
  spaces to `_`, not the primary key or a declared column) are assigned to the record
  as read: no cast, no rules. This needs `output.model`. Narrow it with `file.assign`;
  without `file.assign`, every matching attribute is assigned and a warning is logged
  at load.
- `reject`: `unknown_headers` file error.

Blank headers are ignored (with a warning). Without a header row, `keep` and `assign`
keep extra cells as `"column_<n>"`.

### columns

A mapping of snake_case keys (`/\A[a-z_][a-z0-9_]*\z/`, the attribute name) to options.
At least one column is required. All options are optional.

| Key | Type | Default | Applies to | Notes |
| --- | --- | --- | --- | --- |
| `header` | non-blank string | the key | all | |
| `aliases` | names | `[]` | all | Other accepted headers. A header used twice across columns is an error. |
| `header_pattern` | regexp or list | none | all | Case-insensitive, on the stripped header. |
| `type` | `string` \| `integer` \| `decimal` \| `boolean` \| `date` \| `datetime` | `string` | all | |
| `caster` | class < `ApplicationImport::Casters::Base` | built-in for `type` | all | Replaces the type's caster. `type` still decides which options are allowed. |
| `required` | boolean | `false` | all | Blank gives `required`. |
| `min_length` / `max_length` | integer >= 0 | none | string | `too_short` / `too_long`. min <= max. |
| `min` / `max` | integer / finite number / ISO 8601 date or time | none | integer, decimal, date, datetime | `too_small` / `too_big`. min <= max. |
| `format` | `email` or regexp | none | all | Matched on the cell text as in the file (stripped). `invalid_format`. |
| `inclusion` | non-empty list | none | all | `not_included`. Numeric values compare by value (`1` matches `"1.0"`), others as strings. |
| `date_format` | strptime format | none | date, datetime | Strict: the whole value must match. |
| `decimal_separator` | one character | `file.numbers`, else `.` | decimal | |
| `thousands_separator` | one character | `file.numbers` | integer, decimal | With a separator set, grouping must be exact: with `"."`, `1.234` is accepted but `1.5` is rejected. |

At load:
- A decimal column's effective pair (`file.numbers` merged with its own separators,
  decimal default `.`) must use different separators.
- Column rules run on the value cast from the file, before transformers. Checks on
  transformed values belong in validators.
- Rule errors of every column of a row are collected together.

Casting (blank cells, meaning nil or whitespace, become nil and never reach a caster;
a failed cast gives `invalid_type`):

| Type | Accepts |
| --- | --- |
| `string` | The text as read. |
| `integer` | Base-10 integers. `1.5`, `1e3`, `0x1` and `1_000` are rejected. |
| `decimal` | `BigDecimal`. `NaN`, `Infinity` and `_` are rejected. |
| `boolean` | `true t yes y 1` / `false f no n 0`, case-insensitive. |
| `date` | With `date_format`, that format only. Otherwise ISO 8601, then lenient `Date.parse` needing year, month and day (warned once per run). |
| `datetime` | Same rules, in `Time.zone`. |

### transformers

A list, run in order on each row after cast and column rules. Each entry has exactly one
of `type` (built-in) or `class` (< `ApplicationImport::Transformers::Base`; other keys
become its options). Each returns attributes merged into the row. The Symbol keys it
adds are assigned to the record when the model has a setter for them.

| Type | Keys (required **bold**) | Behavior |
| --- | --- | --- |
| `normalize` | **`attributes`** (names), **`with`** (list of `strip`, `downcase`, `upcase`, `squish`) | String values only; operations in order. |
| `default` | **`attribute`**, **`value`** | Sets `value` (a copy per row) when the attribute is nil, blank or empty. `false` and `0` are kept. |
| `map` | **`attribute`**, **`values`** (mapping), `to` (default: the attribute), `case_sensitive` (default `false`), `strict` (default `false`) | Replaces values through the table; surrounding spaces are ignored. Blank values are left alone. `strict: true`: a value not in the table gives `not_mapped`. With `to` set to another name, `to` is always set (nil when unmapped). |
| `concat` | **`from`** (names), **`to`**, `separator` (string, default `" "`) | Joins non-blank values; all blank gives nil. |
| `context` | **`key`**, **`to`** | Copies `context[key]` (Symbol or String key) into every row; missing gives nil. |

### mapper

Optional. One mapper, run after the transformers. It has exactly one of `type` or
`class` (< `ApplicationImport::Mappers::Base`; other keys become options). It returns
the new attributes Hash.

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `type: rename` → `attributes` | mapping `from: to` (names) | required | `from` is a column / generated key, or a kept unknown header (String, e.g. `Phone`). |
| `type: rename` → `only` | boolean | `false` | `true`: keep only the renamed attributes. |

Renaming onto a declared column that is not itself renamed away is an error at load,
unless `only: true`. Later stages (validator keys, `unique_in_file`) use the names after
the mapper.

### validators

A mapping of stages to lists. Each entry has exactly one of `type` (built-in) or `class`
(< the stage base below); other keys become its options.

| Stage | Runs | Class base / signature | Built-in types |
| --- | --- | --- | --- |
| `file` | Once, before reading, after the file checker. | `Validators::FileValidator#call(source, result)` | none |
| `row` | Each row, on its own. | `Validators::RowValidator#call(row, result)` | `model` |
| `rows` | Each row, in file order, across rows. | `Validators::RowsValidator#call(row, result, cache)` | `unique_in_file` |
| `verify` | Once, on all kept rows. Not with `output.stream`. | `Validators::VerifyValidator#call(rows, result, cache)` | none |

`cache` is one Hash per run, shared by the rows and verify checks and the handler. Keep
state under your own key.

Validators report errors with `row.add_error(code:, message:, column:, details:)`, or by
raising `Errors::RowError.new(msg, line:, column:, code:)` or
`Errors::RowsError.new(msg, lines:, columns:, code:)`. `on_error` applies to all of them.

`type: model` runs the model's own validations (`record.valid?`). Each error becomes a
row error whose code is the error type (`blank`, `taken`, ..., or `invalid` for
message-only errors).

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `model` | class (concrete model) | `output.model` | One of the two is required. |
| `context` | name or list | none (`create` for new records) | A custom context replaces `create`; use `[ create, import ]` to keep `on: :create` validations. |
| `skip` | names | `[]` | Validation kinds (`presence`, `uniqueness`, `length`, ...) or `validate :method` names *not run* in this step, for this import. Same as `import_skip ..., on: :<import>` on the model. The write step still runs them. |
| `except` | names | `[]` | Kinds or error types that still run but whose errors are ignored (`uniqueness` ignores `taken`). |

`type: unique_in_file` gives a `duplicate` error, with details `{ keys:, line: }` of the
first occurrence.

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `keys` | names | required | Attribute names after transformers and mapper. Without transformers or mapper they are checked against the columns at load; otherwise a key missing from a row fails the run (`ConfigError`). |
| `case_sensitive` | boolean | `true` | Strings are stripped before comparing. |

Rows with a blank key, and rows dropped by an error, are neither checked nor remembered.
A remembered row that is skipped later gives way to the next row with its key.

### output

| Key | Type | Default | Modes | Notes |
| --- | --- | --- | --- | --- |
| `mode` | `bulk` \| `save` \| `raw` | `bulk` with `model`, else `raw` | | `bulk`: `Model.import` (activerecord-import) per batch. `save`: `record.save` per row. `raw`: nothing persisted; attributes go to `result.records`. |
| `model` | class (concrete application model) | none | bulk, save (required) | Abstract classes, `ActiveRecord::Base` and Rails' own models (`ActiveStorage::`, `SolidQueue::`, ...) are rejected. |
| `batch_size` | integer >= 1 | `1000` | bulk; stream | Rows per `Model.import` call and per stream batch. |
| `transaction` | boolean | `true` | bulk, save | Each write call runs in one transaction (a savepoint when nested); an abort rolls it back. Each record or batch also gets its own savepoint. |
| `stream` | boolean | `false` | bulk, save | Kept rows are written every `batch_size` rows while reading, then their records are released. Cannot be used with verify validators or a handler overriding `verify`. A transaction only covers one batch. |
| `upsert.conflict_target` | names | required with `upsert` | bulk | Needs a unique index. |
| `upsert.update` | names | required with `upsert` | bulk | Columns updated on conflict (`on_duplicate_key_update`). |
| `import` | mapping | `{}` | bulk | activerecord-import options, passed as-is: `validate`, `validate_with_context`, `validate_uniqueness`, `timestamps`, `recursive`, `batch_size`, `all_or_none`, `on_duplicate_key_update`, `on_duplicate_key_ignore`. The last two cannot be combined with `upsert`. |
| `save` | mapping | `{}` | save | `record.save` options: `validate`, `context`, `touch`. |

At load:
- `upsert`, `import` and `save` outside their modes are errors.
- `transaction`, `stream` or `batch_size` with no effect in the mode only log a warning,
  since they often come from `_config.yml` defaults.
- `upsert` attribute names are checked against the model when its table can be read.

Write failures:
- A row that cannot be written gets `not_saved`, and `on_error` applies to it. This
  covers validation failures, `failed_instances` and a row's database error (e.g. an
  integer out of the column's range). In bulk mode such an error is retried row by row
  to find the culprit.
- Database errors that are not a row's fault fail the run with `unexpected_error`:
  connection lost, query aborted or timed out, lock wait timeout, deadlock or
  serialization failure, read-only.

### on_error

Short form: `on_error: skip` (or `abort`) sets `default`. Mapping form:

| Key | Type | Default | Notes |
| --- | --- | --- | --- |
| `default` | `abort` \| `skip` | `abort` | Action for codes not listed. |
| `allow` | row error codes | `[]` | Error recorded, row kept and written. |
| `skip` | row error codes | `[]` | Error recorded, row dropped, run goes on. A code cannot be in both `allow` and `skip`. |
| `row_errors` | `first` \| `all` | `first` | `first`: a row stops at the first check reporting a non-allowed error. `all`: every check runs and all errors are collected. |
| `max_errors` | integer >= 1, or `null` | `null` (no limit) | More row errors than this gives `too_many_errors`, and the run stops. |

Actions: `abort` records the error and stops the run (status `failed`; nothing more is
written, and an open write transaction is rolled back). File errors always abort.

## Error codes

File errors have no `line`.

| Code | Source |
| --- | --- |
| `invalid_format` | Extension not in `file.formats`. |
| `invalid_name` | Filename does not match `name_pattern`, or contains a NUL byte. |
| `too_large` | Bigger than `max_size`. Details: `size`, `max_size`. |
| `invalid_encoding` | Bytes invalid in the encoding, unmappable characters, or NUL bytes. |
| `empty_file` | No content, no header row, or no data rows. |
| `malformed_csv` | CSV parse error. |
| `field_too_large` | A value longer than `max_field_size`, or an unclosed quote. Details: `line`, `max_field_size`. |
| `too_many_cells` | A record with more cells than `max_columns`. Details: `line`, `cells`, `max_columns`. |
| `missing_headers` / `duplicate_headers` / `ambiguous_headers` / `unknown_headers` | Header matching. |
| `extra_cells` | `extra_cells: reject`. |
| `too_many_errors` | `on_error.max_errors` exceeded. |
| `unexpected_error` | An exception stopped the run. Details: `exception`. |
| `invalid_file` | Default code of a raised `Errors::FileError`. |

Row errors:

| Code | Source |
| --- | --- |
| `required`, `invalid_type`, `too_short`, `too_long`, `too_small`, `too_big`, `invalid_format`, `not_included` | Cast and column rules. |
| `not_mapped` | `map` transformer with `strict: true`. |
| `duplicate` | `unique_in_file`. |
| `blank`, `taken`, `invalid`, ... | `type: model` (the ActiveModel error type). |
| `not_saved` | Write step. |
| `invalid_row` / `rows_conflict` | Default codes of a raised `RowError` / `RowsError`. |
| anything | Codes your own checks add. |

## Result

| Method | Returns |
| --- | --- |
| `status` | `:completed` (no errors), `:completed_with_errors` (allowed or skipped row errors), `:failed` (aborted). |
| `success?` / `failed?` / `dry_run?` | Booleans. |
| `stats` | `{ total:, valid:, invalid:, written: }`. `total` counts data rows read; `valid` is `total - invalid`. |
| `errors` | `ErrorEntry` objects (`line`, `column`, `code`, `message`, `details`); `file_level?` when `line` is nil. |
| `records` | Attribute hashes written in raw mode. |
| `to_h` | `{ status:, dry_run:, stats:, errors:, records: }`. |

`line` is the physical line where the record starts (header = 1). A `RowsError` is
recorded once, on its first line, with `details: { lines:, columns: }`. With
`output.stream`, an error naming an already written line goes to the row being checked.

## Extending

All custom classes are named in the YAML and resolved at load. They must subclass the
base listed.

### Handler hooks

Subclass `ApplicationImport::Handler` (it has `definition` and `context`) and override
only what you need:

| Hook | When | Default |
| --- | --- | --- |
| `validate_file(source, result)` | After the file checker and file validators. | none |
| `map_row(attributes, row)` | After the mapper. Returns the attributes. | unchanged |
| `build_record(attributes, row)` | Returns the record to validate and write. | New `output.model` with the declared columns and generated keys it can set. |
| `validate_row(row, result)` | After row validators. | none |
| `validate_rows(row, result, cache)` | After rows validators, each row in file order. | none |
| `verify(rows, result, cache)` | Once, on the kept rows, before writing. | none |
| `write(rows, writer)` | Write step. Returns the written count. | `writer.call(rows)` |
| `after_import(result)` | Always, last. Its exceptions are logged and reported, never raised. | none |

### Other extension points

| What | Base | Implement |
| --- | --- | --- |
| File checker (`file.checker`) | `ApplicationImport::FileChecker` | Override `call(source, result)` or the private `check_*` methods. |
| Reader (`file.reader`) | `ApplicationImport::Readers::Base` (or `Readers::Csv`) | Private `each_record`, yielding `line, values` for every record. Optional `open`, `close`, `read_headers`. Raise `Errors::FileError` for read problems. |
| Caster (`columns.x.caster`) | `ApplicationImport::Casters::Base` | `call(value)`; `invalid!` (or raising `ArgumentError` / `TypeError`) gives `invalid_type`. Optional `type_name`. |
| Transformer | `ApplicationImport::Transformers::Base` | `call(attributes, row)` returning a Hash or nil. `options`, `context` available. |
| Mapper | `ApplicationImport::Mappers::Base` | `call(attributes, row)` returning the new Hash. |
| Validator | `Validators::FileValidator` / `RowValidator` / `RowsValidator` / `VerifyValidator` | `call` with the stage signature. `options`, `context` available. |
| Runner (`run(..., runner:)`) | `ApplicationImport::Runner` | Override `run_steps` or single steps. |

A `RowError` or `RowsError` must name a line where a data row starts (use `row.line`).
Any other line raises `Errors::UnknownLineError`, which points at a bug in the code that
raised it.

### Skipping model validations during an import

```ruby
class User < ApplicationRecord
  include ApplicationImport::Importable
  import_skip :uniqueness                          # in the model validator step of every import
  import_skip :length, :check_manager, on: :users  # only in the users import
end
```

This only affects the `type: model` validator step. Writing (`record.save`,
`Model.import` with `validate`) and the rest of the app validate as usual. The YAML
equivalent is `skip:` on the model validator.

## Examples

[`example/`](example/):

| File | Shows |
| --- | --- |
| `_config.yml` | Global settings with environment sections. |
| `users.yml` | Full reference: every section and option, with comments. |
| `orders.yml` | Windows-1252, `;` separator, localized numbers, save mode, lenient error policy with `max_errors`. |
| `products.yml` | Streaming bulk upsert, `unknown_headers: assign` with `assign.ignore`. |
| `contacts.yml` | No header row, tab separator, `skip_lines`, transformers, mapper `rename only`, raw output. |
| `members.yml` | Exact headers, custom handler, file checker, reader and caster. |

Each example is parsed by `spec/lib/application_import/configs/definition_parser_spec.rb`.

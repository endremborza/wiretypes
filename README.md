# wiretypes

Rust types and constants as the one source of their TypeScript and Python definitions.

Every struct or enum that crosses a language boundary, and every constant another language needs, carries `#[wire]`, and `wiretypes` renders it as TypeScript and Python, one file per Rust module. The generated files are committed, never edited by hand, and a test fails when they are stale.

## Setup

`cargo add wiretypes`. A crate with wire types depends on `wiretypes` and serde alone: `wiretypes` re-exports the schemars and inventory it builds on.

`wiretypes.toml` names the targets, never a type. Paths are relative to its directory, and either target can be left out:

```toml
regenerate = "WIRETYPES=write cargo test generated_types_are_current"

[ts]
out = "web/src/lib/wire"

[python]
out = "wire"
style = "typeddict"
```

- `regenerate` is the command each generated file's header and the drift error name; by default `WIRETYPES=write cargo test`.
- `style` is `typeddict` (the default) or `dataclass`; the dataclass style refuses a key Python cannot spell as a field, such as `paper-fields`.

The export is a test in the one binary that links every crate with wire types, since a registration is seen only where it is linked:

```rust
#[test]
fn generated_types_are_current() {
    if let Err(e) = wiretypes::sync(concat!(env!("CARGO_MANIFEST_DIR"), "/wiretypes.toml")) {
        panic!("{e}");
    }
}
```

By default it compares the rendered files with the committed ones and fails naming those that differ. With `WIRETYPES=write` it writes them, and removes generated files no module renders anymore. A file under an output directory whose first line lacks the generated header is never touched.

## Marking a type

`#[wire]` goes above the type's `#[derive(..)]`:

```rust
use serde::Serialize;
use wiretypes::wire;

#[wire]
#[derive(Serialize)]
pub struct SearchResult {
    pub name: String,
    #[serde(rename = "semanticId")]
    pub semantic_id: String,
    #[serde(rename = "rawCites", skip_serializing_if = "Option::is_none")]
    pub raw_cites: Option<u32>,
}
```

It derives `schemars::JsonSchema`, so the schema follows every serde attribute (`rename`, `rename_all`, `flatten`, `skip`, enum tagging), and registers the type with its module path through `inventory`.

- The serde derives pick the contract: with `Serialize` the type describes what Rust sends, with `Deserialize` alone what Rust accepts.
- A record that other languages write and Rust reads leniently derives both and marks the fields Rust can do without `#[serde(default)]`: the generated type is what a writer must produce.
- `skip_serializing_if = "Option::is_none"` makes a field absent rather than null (`field?: T`, `NotRequired[T]`); a plain `Option<T>` is a required, nullable field.
- Every type a registered type reaches needs `#[wire]` too; generation fails naming the one that lacks it.
- A generic struct carries `#[wire]` for the derive and is registered per instantiation through an alias: `#[wire] pub type PageJson = PageGen<Option<u64>>;` emits `PageJson`.
- `HashMap`/`HashSet` fields from any crate (hashbrown's, say) are described as the std ones, automatically. A type alias over such a map hides it from that rewrite, so `#[wire]` on the alias also emits an `{Alias}Wire` twin, which a field of the alias type names: `#[schemars(with = "LabelsWire")]`.

## Marking a constant

`#[wire]` on a `const`, or an immutable `static`, whose type is `Serialize` and `JsonSchema` exports its value into its module's file, ahead of the types: an `export const` in TypeScript and a `Final` in Python. The value is serialized when the targets are rendered, so it is whatever Rust evaluates: arithmetic over other constants, a struct literal, an `include!`, or what a `LazyLock` static builds. The name stays the Rust name, `///` docs become comments, and the item keeps its visibility.

```rust
/// Results one search request returns at most.
#[wire]
pub const MAX_RESULTS: usize = 24;
```

```ts
// Results one search request returns at most.
export const MAX_RESULTS = 24;
```

```python
# Results one search request returns at most.
MAX_RESULTS: Final = 24
```

A value whose type is itself a `#[wire]` type is annotated with it: `export const DEFAULTS: Settings = {...}` and `DEFAULTS: Final[Settings] = {...}`, a Python list where the type has a list and a tuple where it has a tuple. Any other array, slice or tuple becomes `[...] as const` in TypeScript and a tuple in Python; any other struct an object literal (`as const`) or a dict. Keys are sorted.

## Output

Each Rust module with registered items becomes one file per target, at its module path under the target's `out`: `app::responses` renders to `responses.ts` and `responses.py` under an `app/` directory. A module with submodules becomes a Python package (`__init__.py`), and every package directory gets an `__init__.py`. Imports between modules are relative.

Names are the Rust names in every language; there are no renames. Modules keep same-named types apart, and a file that would import two types of one name fails generation. Fields are ordered by key, with a union's discriminator first, and `///` docs become comments (TS) or docstrings (Python).

| Rust / serde | TypeScript | Python |
| --- | --- | --- |
| integers, floats | `number` | `int`, `float` |
| `Option<T>` | `T \| null` | `T \| None` |
| `Vec<T>`, `[T; N]`, `Box<[T]>` | `T[]` | `list[T]` |
| tuples | `[A, B]` | `tuple[A, B]` |
| maps | `Record<string, V>` | `dict[str, V]` |
| unit-variant enum | union of string literals | `Literal[...]` |
| tagged enum | discriminated union | one TypedDict per variant (`{Enum}{Variant}`), joined in a `type` alias |
| `serde_json::Value` | `unknown` | `Any` |

Keep the output directories out of formatters and linters, which would make every check fail; type checkers (tsc, svelte-check, pyright) can still read them.

## Internals

| File | Role |
| --- | --- |
| `wiretypes_macro/src/lib.rs` | `#[wire]`: the `JsonSchema` derive, the std-map rewrite, the null-dropping transform for `skip_serializing_if`, the `Wire` impl and the `inventory` registration; on a const or static, the value's and its type's registration (a `LazyLock` static's built value) |
| `wiretypes/src/lib.rs` | `WireType` and `WireConst` registries, `Wire` contract trait, `sync` (render, then write or check) |
| `wiretypes/src/model.rs` | Registry → one schema generator per contract → one `Shape` per registered type, one JSON value per registered constant with its registered type when it has one, grouped by module |
| `wiretypes/src/shape.rs` | JSON Schema → `Shape`, the form the emitters read |
| `wiretypes/src/ts.rs`, `python.rs` | The emitters |
| `wiretypes/src/config.rs`, `output.rs` | `wiretypes.toml`; write and check over the output directories, which only ever touch files carrying the generated header |

Another target language is one emitter module over `Shape` plus a config section.

## License

MIT

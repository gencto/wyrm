//! `#[derive(Params)]` and `#[derive(ParamEnum)]` for
//! `wyrm_link_sdk::driver::params` (ADR 0004).
//!
//! Field attributes: `#[param(default = <lit>, min = <num>, max = <num>,
//! secret, desc = "...", name = "...", enum)]`.
//!
//! * Types: `String`, `bool`, integers (`u8`..`u64`, `i8`..`i64`, `usize`,
//!   `isize`), `f32`/`f64`, and any `ParamEnum` type marked `#[param(enum)]`.
//! * A field without `default` is required.
//! * Integer fields get bounds from their type unless `min`/`max` are given
//!   (`u64`/`usize` are capped at `i64::MAX`), so reading never fails after
//!   validation.
//!
//! Variant attribute for `ParamEnum`: `#[param(name = "...")]`; the default
//! wire name is the snake_case variant name.

use proc_macro::TokenStream;
use proc_macro2::TokenStream as Tokens;
use quote::quote;
use syn::spanned::Spanned;
use syn::{parse_macro_input, Data, DeriveInput, Expr, Fields, Lit, Type, UnOp};

#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Str,
    Bool,
    Int { signed: bool, min: i128, max: i128 },
    Float,
    Enum,
}

fn kind_of(ty: &Type, is_enum: bool) -> syn::Result<Kind> {
    if is_enum {
        return Ok(Kind::Enum);
    }
    let Type::Path(p) = ty else {
        return Err(syn::Error::new_spanned(ty, "unsupported parameter type"));
    };
    let ident = p
        .path
        .segments
        .last()
        .map(|s| s.ident.to_string())
        .unwrap_or_default();
    let int = |signed: bool, min: i128, max: i128| Ok(Kind::Int { signed, min, max });
    let cap = i64::MAX as i128;
    match ident.as_str() {
        "String" => Ok(Kind::Str),
        "bool" => Ok(Kind::Bool),
        "f32" | "f64" => Ok(Kind::Float),
        "u8" => int(false, 0, u8::MAX as i128),
        "u16" => int(false, 0, u16::MAX as i128),
        "u32" => int(false, 0, u32::MAX as i128),
        "u64" | "usize" => int(false, 0, cap),
        "i8" => int(true, i8::MIN as i128, i8::MAX as i128),
        "i16" => int(true, i16::MIN as i128, i16::MAX as i128),
        "i32" => int(true, i32::MIN as i128, i32::MAX as i128),
        "i64" | "isize" => int(true, i64::MIN as i128, cap),
        _ => Err(syn::Error::new_spanned(
            ty,
            "unsupported parameter type; mark ParamEnum types with #[param(enum)]",
        )),
    }
}

#[derive(Default)]
struct FieldAttrs {
    default: Option<Expr>,
    min: Option<Expr>,
    max: Option<Expr>,
    secret: bool,
    desc: Option<String>,
    name: Option<String>,
    is_enum: bool,
}

fn field_attrs(attrs: &[syn::Attribute]) -> syn::Result<FieldAttrs> {
    let mut a = FieldAttrs::default();
    for attr in attrs.iter().filter(|a| a.path().is_ident("param")) {
        attr.parse_nested_meta(|m| {
            if m.path.is_ident("default") {
                a.default = Some(m.value()?.parse()?);
            } else if m.path.is_ident("min") {
                a.min = Some(m.value()?.parse()?);
            } else if m.path.is_ident("max") {
                a.max = Some(m.value()?.parse()?);
            } else if m.path.is_ident("secret") {
                a.secret = true;
            } else if m.path.is_ident("enum") {
                a.is_enum = true;
            } else if m.path.is_ident("desc") {
                let s: syn::LitStr = m.value()?.parse()?;
                a.desc = Some(s.value());
            } else if m.path.is_ident("name") {
                let s: syn::LitStr = m.value()?.parse()?;
                a.name = Some(s.value());
            } else {
                return Err(m.error(
                    "unknown param attribute; expected default, min, max, secret, desc, name or enum",
                ));
            }
            Ok(())
        })?;
    }
    Ok(a)
}

/// A numeric literal (optionally negated) as text, plus whether it is an integer.
fn number(e: &Expr) -> Option<(String, bool)> {
    match e {
        Expr::Lit(l) => match &l.lit {
            Lit::Int(i) => Some((i.base10_digits().to_owned(), true)),
            Lit::Float(f) => Some((f.base10_digits().to_owned(), false)),
            _ => None,
        },
        Expr::Unary(u) if matches!(u.op, UnOp::Neg(_)) => {
            number(&u.expr).map(|(s, i)| (format!("-{s}"), i))
        }
        Expr::Group(g) => number(&g.expr),
        Expr::Paren(p) => number(&p.expr),
        _ => None,
    }
}

fn bound(e: &Expr) -> syn::Result<Tokens> {
    let (text, _) =
        number(e).ok_or_else(|| syn::Error::new_spanned(e, "expected a number literal"))?;
    let v: f64 = text
        .parse()
        .map_err(|_| syn::Error::new_spanned(e, "bad number"))?;
    Ok(quote!(#v))
}

fn default_value(e: &Expr, kind: Kind) -> syn::Result<Tokens> {
    let err = |what: &str| syn::Error::new_spanned(e, format!("default must be {what}"));
    match kind {
        Kind::Str | Kind::Enum => match e {
            Expr::Lit(l) => match &l.lit {
                Lit::Str(s) => Ok(quote!(::wyrm_core::Value::Str(::std::string::String::from(#s)))),
                _ => Err(err("a string literal")),
            },
            _ => Err(err("a string literal")),
        },
        Kind::Bool => match e {
            Expr::Lit(l) => match &l.lit {
                Lit::Bool(b) => Ok(quote!(::wyrm_core::Value::Bool(#b))),
                _ => Err(err("true or false")),
            },
            _ => Err(err("true or false")),
        },
        Kind::Float => {
            let (text, _) = number(e).ok_or_else(|| err("a number literal"))?;
            let v: f64 = text.parse().map_err(|_| err("a number literal"))?;
            Ok(quote!(::wyrm_core::Value::Float(#v)))
        }
        Kind::Int { min, max, .. } => {
            let (text, is_int) = number(e).ok_or_else(|| err("an integer literal"))?;
            if !is_int {
                return Err(err("an integer literal"));
            }
            let v: i128 = text.parse().map_err(|_| err("an integer literal"))?;
            if v < min || v > max {
                return Err(err("within the range of the field type"));
            }
            if v >= 0 {
                let v = v as u64;
                Ok(quote!(::wyrm_core::Value::UInt(#v)))
            } else {
                let v = v as i64;
                Ok(quote!(::wyrm_core::Value::Int(#v)))
            }
        }
    }
}

/// `#[derive(Params)]` on a struct with named fields.
#[proc_macro_derive(Params, attributes(param))]
pub fn derive_params(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    expand_params(&input)
        .unwrap_or_else(syn::Error::into_compile_error)
        .into()
}

fn expand_params(input: &DeriveInput) -> syn::Result<Tokens> {
    if !input.generics.params.is_empty() {
        return Err(syn::Error::new_spanned(
            &input.generics,
            "#[derive(Params)] does not support generics",
        ));
    }
    let Data::Struct(data) = &input.data else {
        return Err(syn::Error::new_spanned(
            &input.ident,
            "#[derive(Params)] needs a struct",
        ));
    };
    let Fields::Named(fields) = &data.fields else {
        return Err(syn::Error::new_spanned(
            &input.ident,
            "#[derive(Params)] needs named fields",
        ));
    };
    let params = quote!(::wyrm_link_sdk::driver::params);
    let (mut specs, mut reads, mut writes) = (Vec::new(), Vec::new(), Vec::new());
    for f in &fields.named {
        let ident = f.ident.as_ref().expect("named field");
        let ty = &f.ty;
        let a = field_attrs(&f.attrs)?;
        let kind = kind_of(ty, a.is_enum)?;
        let name = a.name.clone().unwrap_or_else(|| ident.to_string());
        let tc = match kind {
            Kind::Str => quote!(::wyrm_core::TypeCode::String),
            Kind::Bool => quote!(::wyrm_core::TypeCode::Bool),
            Kind::Int { .. } | Kind::Float => quote!(::wyrm_core::TypeCode::Number),
            Kind::Enum => quote!(::wyrm_core::TypeCode::Enum),
        };
        let mut spec = quote!(#params::ParamSpec::new(#name, #tc));
        if kind == Kind::Enum {
            spec = quote!(#spec.one_of(<#ty as #params::ParamEnum>::NAMES));
        }
        if let Some(d) = &a.default {
            let v = default_value(d, kind)?;
            spec = quote!(#spec.default(#v));
        }
        match kind {
            Kind::Int { min, max, .. } => {
                let lo = match &a.min {
                    Some(e) => bound(e)?,
                    None => {
                        let v = min as f64;
                        quote!(#v)
                    }
                };
                let hi = match &a.max {
                    Some(e) => bound(e)?,
                    None => {
                        let v = max as f64;
                        quote!(#v)
                    }
                };
                spec = quote!(#spec.bounds(#lo, #hi));
            }
            Kind::Float => match (&a.min, &a.max) {
                (None, None) => {}
                (lo, hi) => {
                    let lo = lo
                        .as_ref()
                        .map(bound)
                        .transpose()?
                        .unwrap_or(quote!(f64::MIN));
                    let hi = hi
                        .as_ref()
                        .map(bound)
                        .transpose()?
                        .unwrap_or(quote!(f64::MAX));
                    spec = quote!(#spec.bounds(#lo, #hi));
                }
            },
            _ => {
                if let Some(e) = a.min.as_ref().or(a.max.as_ref()) {
                    return Err(syn::Error::new_spanned(e, "min/max only apply to numbers"));
                }
            }
        }
        if a.secret {
            spec = quote!(#spec.secret());
        }
        if let Some(d) = &a.desc {
            spec = quote!(#spec.desc(#d));
        }
        specs.push(spec);

        reads.push(match kind {
            Kind::Str => quote!(#ident: #params::field::string(m, #name)?),
            Kind::Bool => quote!(#ident: #params::field::bool(m, #name)?),
            Kind::Int { .. } => quote!(#ident: #params::field::int::<#ty>(m, #name)?),
            Kind::Float => quote!(#ident: #params::field::f64(m, #name)? as #ty),
            Kind::Enum => quote!(#ident: #params::field::enumv::<#ty>(m, #name)?),
        });
        let value = match kind {
            Kind::Str => quote!(::wyrm_core::Value::Str(::std::clone::Clone::clone(&self.#ident))),
            Kind::Bool => quote!(::wyrm_core::Value::Bool(self.#ident)),
            Kind::Float => quote!(::wyrm_core::Value::Float(self.#ident as f64)),
            Kind::Int { signed: false, .. } => quote!(::wyrm_core::Value::UInt(self.#ident as u64)),
            Kind::Int { signed: true, .. } => quote!({
                let v = self.#ident as i64;
                if v >= 0 {
                    ::wyrm_core::Value::UInt(v as u64)
                } else {
                    ::wyrm_core::Value::Int(v)
                }
            }),
            Kind::Enum => quote!(::wyrm_core::Value::Str(::std::string::String::from(
                #params::ParamEnum::name(self.#ident)
            ))),
        };
        writes.push(quote!(m.insert(::std::string::String::from(#name), #value);));
    }
    let ident = &input.ident;
    Ok(quote! {
        impl #params::Params for #ident {
            fn schema() -> ::std::vec::Vec<#params::ParamSpec> {
                ::std::vec![#(#specs),*]
            }
            fn from_map(
                m: &::std::collections::BTreeMap<::std::string::String, ::wyrm_core::Value>,
            ) -> ::wyrm_link_sdk::Result<Self> {
                ::std::result::Result::Ok(Self { #(#reads),* })
            }
            fn to_map(&self) -> ::std::collections::BTreeMap<::std::string::String, ::wyrm_core::Value> {
                let mut m = ::std::collections::BTreeMap::new();
                #(#writes)*
                m
            }
        }
    })
}

fn snake(s: &str) -> String {
    let mut out = String::new();
    let chars: Vec<char> = s.chars().collect();
    for (i, c) in chars.iter().enumerate() {
        if c.is_uppercase() {
            let prev_lower =
                i > 0 && (chars[i - 1].is_lowercase() || chars[i - 1].is_ascii_digit());
            let next_lower = chars.get(i + 1).is_some_and(|n| n.is_lowercase());
            if i > 0 && (prev_lower || (next_lower && chars[i - 1].is_uppercase())) {
                out.push('_');
            }
            out.extend(c.to_lowercase());
        } else {
            out.push(*c);
        }
    }
    out
}

/// `#[derive(ParamEnum)]` on a fieldless enum (it must also be `Copy`).
#[proc_macro_derive(ParamEnum, attributes(param))]
pub fn derive_param_enum(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    expand_enum(&input)
        .unwrap_or_else(syn::Error::into_compile_error)
        .into()
}

fn expand_enum(input: &DeriveInput) -> syn::Result<Tokens> {
    let Data::Enum(data) = &input.data else {
        return Err(syn::Error::new_spanned(
            &input.ident,
            "#[derive(ParamEnum)] needs an enum",
        ));
    };
    let mut names = Vec::new();
    let mut idents = Vec::new();
    for v in &data.variants {
        if !matches!(v.fields, Fields::Unit) {
            return Err(syn::Error::new(
                v.span(),
                "ParamEnum variants must have no fields",
            ));
        }
        let mut name = snake(&v.ident.to_string());
        for attr in v.attrs.iter().filter(|a| a.path().is_ident("param")) {
            attr.parse_nested_meta(|m| {
                if m.path.is_ident("name") {
                    let s: syn::LitStr = m.value()?.parse()?;
                    name = s.value();
                    Ok(())
                } else {
                    Err(m.error("expected name = \"...\""))
                }
            })?;
        }
        if names.contains(&name) {
            return Err(syn::Error::new(
                v.span(),
                format!("duplicate name {name:?}"),
            ));
        }
        names.push(name);
        idents.push(&v.ident);
    }
    let ident = &input.ident;
    let params = quote!(::wyrm_link_sdk::driver::params);
    Ok(quote! {
        impl #params::ParamEnum for #ident {
            const NAMES: &'static [&'static str] = &[#(#names),*];
            fn from_name(s: &str) -> ::std::option::Option<Self> {
                match s {
                    #(#names => ::std::option::Option::Some(Self::#idents),)*
                    _ => ::std::option::Option::None,
                }
            }
            fn name(self) -> &'static str {
                match self {
                    #(Self::#idents => #names,)*
                }
            }
        }
    })
}

#[cfg(test)]
mod tests {
    #[test]
    fn snake_case() {
        assert_eq!(super::snake("Holding"), "holding");
        assert_eq!(super::snake("U32WSwap"), "u32_w_swap");
        assert_eq!(super::snake("WriteMultiple"), "write_multiple");
        assert_eq!(super::snake("RTU"), "rtu");
    }
}

//! `#[derive(Args)]`: one struct is an action's declared parameters and the
//! decoder of its arguments (`wyrm_core::args`).

use proc_macro2::TokenStream as Tokens;
use quote::quote;
use syn::{Data, DeriveInput, Expr, Fields, GenericArgument, PathArguments, Type};

#[derive(Default)]
struct Attrs {
    name: Option<String>,
    display: Option<Expr>,
    desc: Option<Expr>,
    placeholder: Option<Expr>,
    editor: Option<Tokens>,
    secret: bool,
    choice: bool,
    index: bool,
    reversed: bool,
    suggest: Option<Expr>,
    min: Option<Expr>,
    max: Option<Expr>,
    trim: bool,
    nonempty: bool,
    flatten: bool,
    absent: Option<Expr>,
    default: Option<Expr>,
}

const KNOWN: &str = "unknown arg attribute; expected name, display, desc, placeholder, editor, \
                     secret, choice, enum, reversed, suggest, min, max, trim, nonempty, flatten, \
                     absent or default";

fn attrs(list: &[syn::Attribute]) -> syn::Result<Attrs> {
    let mut a = Attrs::default();
    for attr in list.iter().filter(|a| a.path().is_ident("arg")) {
        attr.parse_nested_meta(|m| {
            let key = m.path.get_ident().map(ToString::to_string);
            match key.as_deref() {
                Some("name") => a.name = Some(m.value()?.parse::<syn::LitStr>()?.value()),
                Some("display") => a.display = Some(m.value()?.parse()?),
                Some("desc") => a.desc = Some(m.value()?.parse()?),
                Some("placeholder") => a.placeholder = Some(m.value()?.parse()?),
                Some("editor") => {
                    a.editor = Some(crate::editor(&m.value()?.parse::<syn::LitStr>()?)?)
                }
                Some("secret") => a.secret = true,
                Some("choice") => a.choice = true,
                Some("enum") => a.index = true,
                Some("reversed") => a.reversed = true,
                Some("suggest") => a.suggest = Some(m.value()?.parse()?),
                Some("min") => a.min = Some(m.value()?.parse()?),
                Some("max") => a.max = Some(m.value()?.parse()?),
                Some("trim") => a.trim = true,
                Some("nonempty") => a.nonempty = true,
                Some("flatten") => a.flatten = true,
                Some("absent") => a.absent = Some(m.value()?.parse()?),
                Some("default") => a.default = Some(m.value()?.parse()?),
                _ => return Err(m.error(KNOWN)),
            }
            Ok(())
        })?;
    }
    Ok(a)
}

/// `T` of `Wrapper<T>` when the type's last path segment is `wrapper`.
fn inner<'a>(ty: &'a Type, wrapper: &str) -> Option<&'a Type> {
    let Type::Path(p) = ty else {
        return None;
    };
    let seg = p.path.segments.last()?;
    if seg.ident != wrapper {
        return None;
    }
    let PathArguments::AngleBracketed(args) = &seg.arguments else {
        return None;
    };
    match args.args.first()? {
        GenericArgument::Type(t) if args.args.len() == 1 => Some(t),
        _ => None,
    }
}

pub(crate) fn expand(input: &DeriveInput) -> syn::Result<Tokens> {
    if !input.generics.params.is_empty() {
        return Err(syn::Error::new_spanned(
            &input.generics,
            "#[derive(Args)] does not support generics",
        ));
    }
    let named = match &input.data {
        Data::Struct(d) => match &d.fields {
            Fields::Named(f) => Some(&f.named),
            _ => None,
        },
        _ => None,
    };
    let Some(fields) = named else {
        return Err(syn::Error::new_spanned(
            &input.ident,
            "#[derive(Args)] needs a struct with named fields",
        ));
    };
    let args = quote!(::wyrm_core::args);
    let meta = quote!(::wyrm_core::meta);
    let (mut params, mut reads) = (Vec::new(), Vec::new());
    for f in fields {
        let Some(ident) = f.ident.as_ref() else {
            return Err(syn::Error::new_spanned(f, "a named field"));
        };
        let ty = &f.ty;
        let a = attrs(&f.attrs)?;
        let bad = |what: &str| Err(syn::Error::new_spanned(f, what));
        if a.flatten {
            if a.name.is_some() || a.choice || a.index || a.absent.is_some() {
                return bad("flatten takes no other attribute");
            }
            params.push(quote!(out.extend(<#ty as #args::Args>::params());));
            reads.push(quote!(#ident: <#ty as #args::Args>::read(r)?));
            continue;
        }
        if a.choice && a.index {
            return bad("choice (by name) or enum (by index), not both");
        }
        if a.reversed && !(a.choice || a.index) {
            return bad("reversed needs choice or enum");
        }
        if a.trim && (a.choice || a.index) {
            return bad("trim is for text");
        }
        if a.suggest.is_some() && (a.choice || a.index) {
            return bad("suggest lists examples of a free text; a closed set is choice or enum");
        }
        if a.absent.is_some() && a.default.is_some() {
            return bad("absent (not published) or default (published), not both");
        }
        if a.secret && a.editor.is_some() {
            return bad("a secret has the password editor");
        }
        let option = inner(ty, "Option");
        let fallback = a.absent.as_ref().or(a.default.as_ref());
        if option.is_some() && fallback.is_some() {
            return bad("an Option field has no value when absent");
        }
        let value_ty = option.unwrap_or(ty);
        // a list of names of one set: `#[arg(choice)] Vec<T>`
        let list = if a.choice {
            inner(value_ty, "Vec")
        } else {
            None
        };
        let set_ty = list.unwrap_or(value_ty);
        let name = a.name.clone().unwrap_or_else(|| ident.to_string());

        let (code, decode) = if a.choice {
            match list {
                Some(_) => (
                    quote!(::wyrm_core::TypeCode::Array),
                    quote!(#args::names::<#set_ty>),
                ),
                None => (
                    quote!(::wyrm_core::TypeCode::String),
                    quote!(#args::by_name::<#set_ty>),
                ),
            }
        } else if a.index {
            (
                quote!(::wyrm_core::TypeCode::Enum),
                quote!(#args::by_index::<#set_ty>),
            )
        } else if a.trim {
            (
                quote!(<#value_ty as #args::ArgValue>::TYPE),
                quote!(#args::trimmed),
            )
        } else {
            (
                quote!(<#value_ty as #args::ArgValue>::TYPE),
                quote!(<#value_ty as #args::ArgValue>::from_value),
            )
        };

        let mut p = quote!(#meta::ParamMeta::of(#code));
        let required = option.is_none() && fallback.is_none();
        if required {
            p = quote!(#p.required(true));
        }
        if (a.choice && list.is_none()) || a.index {
            let names = quote!(<#set_ty as ::wyrm_core::named::Named>::NAMES.iter().copied());
            p = if a.reversed {
                quote!(#p.enum_values(#names.rev()))
            } else {
                quote!(#p.enum_values(#names))
            };
        }
        if let Some(e) = &a.suggest {
            p = quote!(#p.enum_values(#e));
        }
        if let Some(e) = &a.display {
            p = quote!(#p.display(#e));
        }
        if let Some(e) = &a.desc {
            p = quote!(#p.description(#e));
        }
        if let Some(e) = &a.placeholder {
            p = quote!(#p.placeholder(#e));
        }
        if a.secret {
            p = quote!(#p.editor(#meta::Editor::Password));
        }
        if let Some(e) = &a.editor {
            p = quote!(#p.editor(#e));
        }
        let p = match &a.default {
            Some(e) => quote!({
                let mut p = #p;
                let v: #ty = #e;
                p.default = ::std::option::Option::Some(::wyrm_core::Value::from(v));
                p
            }),
            None => p,
        };
        params.push(quote!(out.push((#name, #p));));

        let field = if a.nonempty {
            quote!(r.take(#name).nonempty())
        } else {
            quote!(r.take(#name))
        };
        let take = match (option.is_some(), fallback) {
            (true, _) => quote!(#field.optional(#decode)?),
            (false, Some(e)) => quote!(match #field.optional(#decode)? {
                ::std::option::Option::Some(v) => v,
                ::std::option::Option::None => #e,
            }),
            (false, None) => quote!(#field.required(#decode)?),
        };
        let mut checks = Vec::new();
        for (bound, check) in [(&a.min, quote!(at_least)), (&a.max, quote!(at_most))] {
            let Some(e) = bound else { continue };
            checks.push(if option.is_some() {
                quote!(if let ::std::option::Option::Some(x) = &v {
                    #args::#check(#name, x, #e)?;
                })
            } else {
                quote!(#args::#check(#name, &v, #e)?;)
            });
        }
        reads.push(quote!(#ident: {
            let v: #ty = #take;
            #(#checks)*
            v
        }));
    }
    let ident = &input.ident;
    Ok(quote! {
        impl #args::Args for #ident {
            fn params() -> ::std::vec::Vec<(&'static str, #meta::ParamMeta)> {
                let mut out = ::std::vec::Vec::new();
                #(#params)*
                out
            }
            fn read(
                r: &mut #args::Reader<'_>,
            ) -> ::std::result::Result<Self, #args::ArgError> {
                ::std::result::Result::Ok(Self { #(#reads),* })
            }
        }
    })
}

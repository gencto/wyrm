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

const KNOWN: &str = "unknown param attribute of an action argument; expected name, display, desc, placeholder, editor, \
                     secret, choice, enum, reversed, suggest, min, max, trim, nonempty, flatten, \
                     absent or default";

fn attrs(list: &[syn::Attribute]) -> syn::Result<Attrs> {
    let mut a = Attrs::default();
    for attr in list.iter().filter(|a| a.path().is_ident("param")) {
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

/// What the attributes of one field must not combine.
fn check(f: &syn::Field, a: &Attrs, option: bool) -> syn::Result<()> {
    let bad = |what: &str| Err(syn::Error::new_spanned(f, what));
    let set = a.choice || a.index;
    if a.choice && a.index {
        return bad("choice (by name) or enum (by index), not both");
    }
    if a.reversed && !set {
        return bad("reversed needs choice or enum");
    }
    if a.trim && a.index {
        return bad("trim is for text: an enum is read by its index");
    }

    if a.suggest.is_some() && set {
        return bad("suggest lists examples of a free text; a closed set is choice or enum");
    }
    if a.absent.is_some() && a.default.is_some() {
        return bad("absent (not published) or default (published), not both");
    }
    if a.secret && a.editor.is_some() {
        return bad("a secret has the password editor");
    }
    if option && (a.absent.is_some() || a.default.is_some()) {
        return bad("an Option field has no value when absent");
    }
    Ok(())
}

/// One field: its type without `Option`, and the set of a `choice`/`enum`.
struct Shape<'a> {
    ty: &'a Type,
    option: bool,
    value_ty: &'a Type,
    /// `#[param(choice)] Vec<T>`: a list of names of one set.
    list: bool,
    set_ty: &'a Type,
}

impl<'a> Shape<'a> {
    fn of(ty: &'a Type, a: &Attrs) -> Self {
        let option = inner(ty, "Option");
        let value_ty = option.unwrap_or(ty);
        let list = if a.choice {
            inner(value_ty, "Vec")
        } else {
            None
        };
        Shape {
            ty,
            option: option.is_some(),
            value_ty,
            list: list.is_some(),
            set_ty: list.unwrap_or(value_ty),
        }
    }

    /// The declared `type` and the function that decodes one value.
    fn codec(&self, a: &Attrs) -> (Tokens, Tokens) {
        let args = quote!(::wyrm_core::args);
        let (value_ty, set_ty) = (self.value_ty, self.set_ty);
        if a.secret && a.trim {
            // the one secret that is trimmed, by its own decoder
            return (
                quote!(<#value_ty as #args::PastedSecretArg>::TYPE),
                quote!(<#value_ty as #args::PastedSecretArg>::pasted),
            );
        }
        if a.choice && self.list {
            (
                quote!(::wyrm_core::TypeCode::Array),
                quote!(#args::names::<#set_ty>),
            )
        } else if a.choice && a.trim {
            (
                quote!(::wyrm_core::TypeCode::String),
                quote!(#args::by_name_trimmed::<#set_ty>),
            )
        } else if a.choice {
            (
                quote!(::wyrm_core::TypeCode::String),
                quote!(#args::by_name::<#set_ty>),
            )
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
        }
    }
}

/// The `ParamMeta` one field declares.
fn declared(sh: &Shape<'_>, a: &Attrs, code: &Tokens) -> Tokens {
    let meta = quote!(::wyrm_core::meta);
    let (ty, set_ty) = (sh.ty, sh.set_ty);
    let mut p = quote!(#meta::ParamMeta::of(#code));
    if !sh.option && a.absent.is_none() && a.default.is_none() {
        p = quote!(#p.required(true));
    }
    if (a.choice && !sh.list) || a.index {
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
    match &a.default {
        Some(e) => quote!({
            let mut p = #p;
            let v: #ty = #e;
            p.default = ::std::option::Option::Some(::wyrm_core::Value::from(v));
            p
        }),
        None => p,
    }
}

/// The expression that takes one field out of the arguments.
fn reading(sh: &Shape<'_>, a: &Attrs, name: &str, decode: &Tokens) -> Tokens {
    let args = quote!(::wyrm_core::args);
    let ty = sh.ty;
    // an empty text is not there; white space counts only for a trimmed field
    let field = match (a.nonempty, a.trim) {
        (true, true) => quote!(r.take(#name).nonblank()),
        (true, false) => quote!(r.take(#name).nonempty()),
        (false, _) => quote!(r.take(#name)),
    };
    let take = match (sh.option, a.absent.as_ref().or(a.default.as_ref())) {
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
        checks.push(if sh.option {
            quote!(if let ::std::option::Option::Some(x) = &v {
                #args::#check(#name, x, #e)?;
            })
        } else {
            quote!(#args::#check(#name, &v, #e)?;)
        });
    }
    // `secret` compiles only on a type that keeps a secret (zeroized, no value
    // in `Debug`): a `String` here is a compile error
    // and `secret, trim` only on the one kind that is trimmed, a pasted token
    // (its type cuts the white space itself)
    let secret = match (a.secret, a.trim) {
        (true, false) => {
            let value_ty = sh.value_ty;
            quote!({
                fn keeps_a_secret<T: #args::SecretArg>() {}
                keeps_a_secret::<#value_ty>();
            })
        }
        // the type's own decoder is used: it compiles only on a pasted token
        (true, true) | (false, _) => quote!(),
    };
    quote!({
        #secret
        let v: #ty = #take;
        #(#checks)*
        v
    })
}

/// What `#[param(flatten)]` stands beside: nothing. Another attribute there
/// would be dropped without a word.
fn only_flatten(f: &syn::Field, a: &Attrs) -> syn::Result<()> {
    let other = a.name.is_some()
        || a.display.is_some()
        || a.desc.is_some()
        || a.placeholder.is_some()
        || a.editor.is_some()
        || a.secret
        || a.choice
        || a.index
        || a.reversed
        || a.suggest.is_some()
        || a.min.is_some()
        || a.max.is_some()
        || a.trim
        || a.nonempty
        || a.absent.is_some()
        || a.default.is_some();
    if other {
        return Err(syn::Error::new_spanned(
            f,
            "flatten takes no other attribute: say it on the fields of the flattened struct",
        ));
    }
    Ok(())
}

/// What the derive makes of the fields.
#[derive(Default)]
struct Made {
    /// Statements that declare the parameters, in field order.
    params: Vec<Tokens>,
    /// The initializer of each field.
    reads: Vec<Tokens>,
    /// The parameter names of the struct's own fields.
    own: Vec<String>,
    /// The types of the flattened structs.
    flat: Vec<Type>,
}

/// One field into `made`; a second field of one name is refused here, a name
/// that comes again through `flatten` by the `const` check of [`expand`].
fn field(f: &syn::Field, made: &mut Made) -> syn::Result<()> {
    let args = quote!(::wyrm_core::args);
    let Some(ident) = f.ident.as_ref() else {
        return Err(syn::Error::new_spanned(f, "a named field"));
    };
    let ty = &f.ty;
    let a = attrs(&f.attrs)?;
    if a.flatten {
        only_flatten(f, &a)?;
        made.params
            .push(quote!(out.extend(<#ty as #args::Args>::params());));
        made.reads
            .push(quote!(#ident: <#ty as #args::Args>::read(r)?));
        made.flat.push(ty.clone());
        return Ok(());
    }
    let sh = Shape::of(ty, &a);
    check(f, &a, sh.option)?;
    let name = a.name.clone().unwrap_or_else(|| ident.to_string());
    if made.own.contains(&name) {
        return Err(syn::Error::new_spanned(
            f,
            format!("two fields are the parameter {name:?}: a name is one field"),
        ));
    }
    let (code, decode) = sh.codec(&a);
    let p = declared(&sh, &a, &code);
    let read = reading(&sh, &a, &name, &decode);
    made.params.push(quote!(out.push((#name, #p));));
    made.reads.push(quote!(#ident: #read));
    made.own.push(name);
    Ok(())
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
    let mut made = Made::default();
    for f in fields {
        field(f, &mut made)?;
    }
    let Made {
        params,
        reads,
        own,
        flat,
    } = made;
    let ident = &input.ident;
    let twice = format!(
        "{ident}: a parameter name is declared twice (by a field and a flattened struct, or by \
         two flattened structs): a name is one field"
    );
    Ok(quote! {
        // a name that comes a second time through `flatten`: a compile error
        const _: () = ::core::assert!(
            !<#ident as #args::Args>::NAMES.repeats_in(&<#ident as #args::Args>::NAMES),
            #twice
        );
        impl #args::Args for #ident {
            const NAMES: #args::Names = #args::Names {
                own: &[#(#own),*],
                flat: &[#(&<#flat as #args::Args>::NAMES),*],
            };
            fn params() -> ::std::vec::Vec<(&'static str, #meta::ParamMeta)> {
                let mut out = ::std::vec::Vec::new();
                #(#params)*
                out
            }
            fn read(
                r: &mut #args::Reader,
            ) -> ::std::result::Result<Self, #args::ArgError> {
                ::std::result::Result::Ok(Self { #(#reads),* })
            }
        }
    })
}

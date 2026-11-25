//! The closed sets of node parameters that the engine reads (review T5): one
//! declaration each, used by the catalog (`choices`, `default`), the check of a
//! definition ([`crate::nodes::ports`]) and the node at run time. A definition
//! keeps the names as text; a name outside a set refuses the definition.

wyrm_core::name_enum! {
    /// The type of a node parameter in the catalog (`params[].type` of `node_types`).
    pub enum ParamTy as "parameter type" {
        Number => "number",
        String => "string",
        Bool => "bool",
        Map => "map",
        /// Of names.
        Array => "array",
        /// Any value.
        Dynamic => "dynamic",
    }
}

wyrm_core::name_enum! {
    /// `expression.trigger`: calculate on any input, or once all have a value.
    pub enum Trigger as "trigger" {
        Any => "any",
        All => "all",
    }
}

wyrm_core::name_enum! {
    /// `expression.quality`: the result's quality.
    pub enum QualityMode as "quality" {
        /// The worst input's.
        Worst => "worst",
        /// Always good.
        Ignore => "ignore",
        /// Set by the script (`{v, q}`); a result without a valid one is bad.
        Custom => "custom",
    }
}

wyrm_core::name_enum! {
    /// `window.kind`.
    pub enum WindowKind as "kind" {
        /// Back to back.
        Tumbling => "tumbling",
        /// The last `size_s` at each sample.
        Sliding => "sliding",
    }
}

wyrm_core::name_enum! {
    /// `window.fn`: what a window gives.
    pub enum WindowFn as "fn" {
        Avg => "avg",
        Min => "min",
        Max => "max",
        Sum => "sum",
        Count => "count",
        Rate => "rate",
    }
}

wyrm_core::name_enum! {
    /// `alarm.on_bad`: what a bad sample does.
    pub enum OnBad as "on_bad" {
        /// Nothing changes.
        Hold => "hold",
        Clear => "clear",
        Raise => "raise",
    }
}

wyrm_core::name_enum! {
    /// `latch.reset`.
    pub enum Reset as "reset" {
        /// Only the reset input clears it.
        Manual => "manual",
        /// Also `in` going false.
        Auto => "auto",
    }
}

wyrm_core::name_enum! {
    /// `invoke.on`: which samples on `in` run the action.
    pub enum InvokeOn as "on" {
        Any => "any",
        /// A bool going true.
        Rising => "rising",
        /// A bool going false.
        Falling => "falling",
        Change => "change",
    }
}

wyrm_core::name_enum! {
    /// `set.on` with `auto_run`: every sample, or a changed value only.
    pub enum SetOn as "on" {
        Change => "change",
        Any => "any",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::nodes::pick_of;
    use wyrm_core::Value;

    /// The sets are the lists the catalog and the check wrote by hand before, in the
    /// catalog's order: `node_types` sends the same `choices`.
    #[test]
    fn the_sets_are_the_lists_they_replace() {
        assert_eq!(
            ParamTy::NAMES,
            ["number", "string", "bool", "map", "array", "dynamic"]
        );
        assert_eq!(Trigger::NAMES, ["any", "all"]);
        assert_eq!(QualityMode::NAMES, ["worst", "ignore", "custom"]);
        assert_eq!(WindowKind::NAMES, ["tumbling", "sliding"]);
        assert_eq!(
            WindowFn::NAMES,
            ["avg", "min", "max", "sum", "count", "rate"]
        );
        assert_eq!(OnBad::NAMES, ["hold", "clear", "raise"]);
        assert_eq!(Reset::NAMES, ["manual", "auto"]);
        assert_eq!(InvokeOn::NAMES, ["any", "rising", "falling", "change"]);
        // the check listed `["any", "change"]`, the catalog `["change", "any"]`: one order now
        assert_eq!(SetOn::NAMES, ["change", "any"]);
    }

    /// A definition names one of the set, or leaves it out (the default); anything else
    /// refuses it with the text the check gave before.
    #[test]
    fn a_definition_names_one_of_the_set() {
        let cfg = |v: Value| crate::def::Map::from([("quality".to_owned(), v)]);
        for q in QualityMode::ALL {
            assert_eq!(
                pick_of(&cfg(Value::from(q.name())), "quality", QualityMode::Worst).ok(),
                Some(*q)
            );
        }
        assert_eq!(
            pick_of(&crate::def::Map::new(), "quality", QualityMode::Worst).ok(),
            Some(QualityMode::Worst)
        );
        for bad in [Value::from("Custom"), Value::from(""), Value::from("good")] {
            let e = pick_of(&cfg(bad), "quality", QualityMode::Worst).unwrap_err();
            assert!(
                matches!(&e, crate::nodes::ConfigError::OneOf { field, names }
                    if field == "quality" && *names == QualityMode::NAMES),
                "{e:?}"
            );
            assert_eq!(
                e.to_string(),
                r#"quality: one of ["worst", "ignore", "custom"]"#
            );
        }
        assert!(pick_of(&cfg(Value::UInt(1)), "quality", QualityMode::Worst).is_err());
    }
}

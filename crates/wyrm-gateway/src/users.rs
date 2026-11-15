//! User accounts, persisted with `wyrm-state` (the broker owns them, ADR
//! 0003). Passwords are argon2id PHC strings; hashing happens before the
//! operation is logged, so the WAL never sees a plaintext password.

use argon2::password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, SaltString};
use argon2::{Argon2, PasswordVerifier};
use minicbor::{decode, encode, Decode, Decoder, Encode, Encoder};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::collections::BTreeMap;
use wyrm_core::Perm;

/// Longest accepted password: argon2 input is bounded to keep logins cheap.
pub const MAX_PASSWORD: usize = 1024;
pub const MIN_PASSWORD: usize = 8;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct User {
    /// argon2id PHC string.
    pub hash: String,
    pub roles: Vec<String>,
    pub disabled: bool,
    /// Set from the store-wide counter at creation, password change and
    /// disable: older sessions stop, also those of an earlier user with the
    /// same name (the counter never goes back).
    pub gen: u64,
}

#[derive(Debug, Encode, Decode)]
pub enum Op {
    #[n(0)]
    AddUser {
        #[n(0)]
        name: String,
        #[n(1)]
        hash: String,
        #[n(2)]
        roles: Vec<String>,
    },
    #[n(1)]
    SetPassword {
        #[n(0)]
        name: String,
        #[n(1)]
        hash: String,
    },
    #[n(2)]
    SetRoles {
        #[n(0)]
        name: String,
        #[n(1)]
        roles: Vec<String>,
    },
    #[n(3)]
    Disable {
        #[n(0)]
        name: String,
        #[n(1)]
        disabled: bool,
    },
    #[n(4)]
    RemoveUser(#[n(0)] String),
    /// Replace the grants of one role (`sys/~act/update_permissions`); the
    /// stored list overrides the configured role of the same name.
    #[n(5)]
    SetRole {
        #[n(0)]
        role: String,
        /// In match order.
        #[n(1)]
        grants: Vec<RoleGrant>,
    },
    /// A device key of `user` (ADR 0050): only its public key.
    #[n(6)]
    AddDevice {
        #[n(0)]
        id: String,
        #[n(1)]
        user: String,
        #[n(2)]
        name: String,
        #[n(3)]
        platform: String,
        /// `es256` or `rs256` (see [`crate::devices::KeyAlg`]).
        #[n(4)]
        alg: String,
        #[n(5)]
        public_key: Vec<u8>,
        #[n(6)]
        attestation: Option<Vec<u8>>,
        /// Also the time the password was last used with this device.
        #[n(7)]
        at: u64,
    },
    /// A device login.
    #[n(7)]
    DeviceUsed {
        #[n(0)]
        id: String,
        #[n(1)]
        at: u64,
    },
    /// The password was used on the device (a password login that named it).
    #[n(8)]
    DevicePassword {
        #[n(0)]
        id: String,
        #[n(1)]
        at: u64,
    },
    /// An admin removed another user's device: the record stays as a tombstone, so the
    /// device hears why and its owner sees who.
    #[n(9)]
    RemoveDevice {
        #[n(0)]
        id: String,
        #[n(1)]
        by: String,
        #[n(2)]
        at: u64,
    },
    /// The record goes (its owner turned it off, or forgot a tombstone).
    #[n(10)]
    ForgetDevice(#[n(0)] String),
    /// Sign out everywhere: a new generation ends every session and signs every device
    /// out, as a password change does.
    #[n(11)]
    EndSessions(#[n(0)] String),
}

/// Device records one user may have, tombstones and signed-out ones included; past it the
/// oldest that cannot log in go first.
pub const MAX_DEVICE_RECORDS: usize = 32;

/// A device key (ADR 0050 §1.1). The gateway keeps the public key only.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Device {
    pub user: String,
    /// The user's generation at registration: a later one signs the device out.
    pub user_gen: u64,
    pub name: String,
    pub platform: String,
    pub alg: String,
    pub public_key: Vec<u8>,
    pub attestation: Option<Vec<u8>>,
    pub added: u64,
    pub last_used: u64,
    /// When the password was last used on this device.
    pub password_at: u64,
    /// `(by, at)` when an admin removed it.
    pub removed: Option<(String, u64)>,
}

/// One grant of a role as the store keeps it. The level is a [`Perm`] in
/// memory and its wire code on disk, in the layout SCHEMA 5 wrote for
/// `(String, u8)`: CBOR `[key, code]` in the WAL, the same tuple in the
/// snapshot. A code this build does not know refuses the record, so the
/// store does not open (ADR 0029 item 12): a grant is never dropped on
/// read, and a role never widens because a restricting grant before a broad
/// one went missing (typing audit 2026-11-15, T4).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoleGrant {
    /// Key expression; `{site}` stands for the gateway's site.
    pub key: String,
    pub perm: Perm,
}

fn unknown_code(key: &str, code: u8) -> String {
    format!("role grant on {key}: unknown level code {code} (written by a newer WYRM?)")
}

impl<C> Encode<C> for RoleGrant {
    fn encode<W: encode::Write>(
        &self,
        e: &mut Encoder<W>,
        _ctx: &mut C,
    ) -> Result<(), encode::Error<W::Error>> {
        e.array(2)?.str(&self.key)?.u8(self.perm.code())?;
        Ok(())
    }
}

impl<'b, C> Decode<'b, C> for RoleGrant {
    fn decode(d: &mut Decoder<'b>, _ctx: &mut C) -> Result<Self, decode::Error> {
        if d.array()? != Some(2) {
            return Err(decode::Error::message(
                "role grant: [key, level code] expected",
            ));
        }
        let key = d.str()?.to_owned();
        let code = d.u8()?;
        let perm =
            Perm::try_from(code).map_err(|c| decode::Error::message(unknown_code(&key, c)))?;
        Ok(Self { key, perm })
    }
}

impl Serialize for RoleGrant {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        (&self.key, self.perm.code()).serialize(s)
    }
}

impl<'de> Deserialize<'de> for RoleGrant {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let (key, code) = <(String, u8)>::deserialize(d)?;
        let perm =
            Perm::try_from(code).map_err(|c| serde::de::Error::custom(unknown_code(&key, c)))?;
        Ok(Self { key, perm })
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct UserDb {
    pub users: BTreeMap<String, User>,
    /// Next generation; survives `RemoveUser`.
    pub next_gen: u64,
    /// Roles changed at runtime: role → grants in match order.
    #[serde(default)]
    pub roles: BTreeMap<String, Vec<RoleGrant>>,
    /// Device keys by id (ADR 0050).
    #[serde(default)]
    pub devices: BTreeMap<String, Device>,
}

impl UserDb {
    fn bump(&mut self) -> u64 {
        self.next_gen += 1;
        self.next_gen
    }

    fn get_mut(&mut self, name: &str) -> Result<&mut User, String> {
        self.users
            .get_mut(name)
            .ok_or_else(|| format!("no user {name}"))
    }

    fn device_mut(&mut self, id: &str) -> Result<&mut Device, String> {
        self.devices
            .get_mut(id)
            .ok_or_else(|| format!("no device {id}"))
    }

    /// Can `d` log in now: not removed, and its owner's generation has not moved.
    pub fn device_active(&self, d: &Device) -> bool {
        d.removed.is_none() && self.users.get(&d.user).is_some_and(|u| u.gen == d.user_gen)
    }

    /// Keep `user` within [`MAX_DEVICE_RECORDS`]: drop the oldest records that cannot log in.
    fn prune_devices(&mut self, user: &str) {
        loop {
            let mine: Vec<(&String, &Device)> = self
                .devices
                .iter()
                .filter(|(_, d)| d.user == user)
                .collect();
            if mine.len() <= MAX_DEVICE_RECORDS {
                return;
            }
            let Some(oldest) = mine
                .iter()
                .filter(|(_, d)| !self.device_active(d))
                .min_by_key(|(id, d)| (d.removed.as_ref().map_or(d.added, |r| r.1), *id))
                .map(|(id, _)| (*id).clone())
            else {
                return;
            };
            self.devices.remove(&oldest);
        }
    }
}

impl wyrm_state::State for UserDb {
    // 4: grant keys renamed by spec 0.2.0 (`SetRole` replays them renamed)
    // 5: device keys (ADR 0050)
    const SCHEMA: u32 = 5;
    type Op = Op;

    fn apply(&mut self, op: &Op) -> Result<(), String> {
        match op {
            Op::AddUser { name, hash, roles } => {
                if self.users.contains_key(name) {
                    return Err(format!("user {name} exists"));
                }
                let gen = self.bump();
                self.users.insert(
                    name.clone(),
                    User {
                        hash: hash.clone(),
                        roles: roles.clone(),
                        disabled: false,
                        gen,
                    },
                );
            }
            Op::SetPassword { name, hash } => {
                let gen = self.bump();
                let u = self.get_mut(name)?;
                u.hash = hash.clone();
                u.gen = gen;
            }
            Op::SetRoles { name, roles } => {
                self.get_mut(name)?.roles = roles.clone();
            }
            Op::Disable { name, disabled } => {
                let was = self.get_mut(name)?.disabled;
                let gen = (*disabled && !was).then(|| self.bump());
                let u = self.get_mut(name)?;
                if let Some(g) = gen {
                    u.gen = g;
                }
                u.disabled = *disabled;
            }
            Op::RemoveUser(name) => {
                self.users
                    .remove(name)
                    .ok_or_else(|| format!("no user {name}"))?;
                self.devices.retain(|_, d| &d.user != name);
            }
            Op::AddDevice {
                id,
                user,
                name,
                platform,
                alg,
                public_key,
                attestation,
                at,
            } => {
                if self.devices.contains_key(id) {
                    return Err(format!("device {id} exists"));
                }
                let user_gen = self.get_mut(user)?.gen;
                self.devices.insert(
                    id.clone(),
                    Device {
                        user: user.clone(),
                        user_gen,
                        name: name.clone(),
                        platform: platform.clone(),
                        alg: alg.clone(),
                        public_key: public_key.clone(),
                        attestation: attestation.clone(),
                        added: *at,
                        last_used: *at,
                        password_at: *at,
                        removed: None,
                    },
                );
                self.prune_devices(user);
            }
            Op::DeviceUsed { id, at } => self.device_mut(id)?.last_used = *at,
            Op::DevicePassword { id, at } => self.device_mut(id)?.password_at = *at,
            Op::RemoveDevice { id, by, at } => {
                let d = self.device_mut(id)?;
                if d.removed.is_none() {
                    d.removed = Some((by.clone(), *at));
                }
                let user = d.user.clone();
                self.prune_devices(&user);
            }
            Op::ForgetDevice(id) => {
                self.devices
                    .remove(id)
                    .ok_or_else(|| format!("no device {id}"))?;
            }
            Op::EndSessions(name) => {
                let gen = self.bump();
                self.get_mut(name)?.gen = gen;
            }
            Op::SetRole { role, grants } => {
                if !valid_name(role) {
                    return Err(format!("bad role name {role:?}"));
                }
                // keys stored before spec 0.2.0 under their new names
                let grants = grants
                    .iter()
                    .map(|g| RoleGrant {
                        key: wyrm_core::keyspace::renamed(&g.key).into_owned(),
                        perm: g.perm,
                    })
                    .collect();
                self.roles.insert(role.clone(), grants);
            }
        }
        Ok(())
    }
}

/// User names: 1–64 of `[A-Za-z0-9._-]`, not starting with `.` or `-`.
pub fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 64
        && !name.starts_with(['.', '-'])
        && name
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
}

pub fn check_password(pw: &str) -> Result<(), String> {
    if pw.chars().count() < MIN_PASSWORD {
        return Err(format!("password shorter than {MIN_PASSWORD}"));
    }
    if pw.len() > MAX_PASSWORD {
        return Err(format!("password longer than {MAX_PASSWORD} bytes"));
    }
    Ok(())
}

/// argon2id with a fresh salt. CPU-heavy: call from a blocking thread.
pub fn hash_password(pw: &str) -> Result<String, String> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(pw.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| format!("argon2: {e}"))
}

/// Verify against a PHC string; `None` runs a dummy verify of the same cost
/// so unknown names take as long as wrong passwords.
pub fn verify_password(pw: &str, hash: Option<&str>) -> bool {
    static DUMMY: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let dummy = DUMMY.get_or_init(|| hash_password("wyrm-gateway-dummy").unwrap_or_default());
    let (phc, real) = match hash {
        Some(h) => (h, true),
        None => (dummy.as_str(), false),
    };
    let ok = PasswordHash::new(phc)
        .map(|h| Argon2::default().verify_password(pw.as_bytes(), &h).is_ok())
        .unwrap_or(false);
    ok && real
}

#[cfg(test)]
mod tests {
    use super::*;
    use wyrm_state::State;

    fn grant(key: &str, perm: Perm) -> RoleGrant {
        RoleGrant {
            key: key.into(),
            perm,
        }
    }

    #[test]
    fn grant_keys_before_spec_0_2_replay_renamed() {
        let mut db = UserDb::default();
        db.apply(&Op::SetRole {
            role: "ops".into(),
            grants: vec![
                grant("wy/{site}/down/**", Perm::Write),
                grant("wy/**", Perm::List),
            ],
        })
        .unwrap();
        assert_eq!(
            db.roles["ops"],
            [
                grant("wy/{site}/downstream/**", Perm::Write),
                grant("wy/**", Perm::List)
            ]
        );
    }

    /// The users store as SCHEMA 5 wrote it: the same snapshot layout and the same `SetRole`
    /// record, the level a bare code that nothing checks.
    mod old {
        use super::super::{Device, User};
        use minicbor::{Decode, Encode};
        use serde::{Deserialize, Serialize};
        use std::collections::BTreeMap;

        #[derive(Debug, Clone, Default, Serialize, Deserialize)]
        pub struct Db {
            pub users: BTreeMap<String, User>,
            pub next_gen: u64,
            pub roles: BTreeMap<String, Vec<(String, u8)>>,
            pub devices: BTreeMap<String, Device>,
        }

        #[derive(Debug, Encode, Decode)]
        pub enum Op {
            #[n(5)]
            SetRole {
                #[n(0)]
                role: String,
                #[n(1)]
                grants: Vec<(String, u8)>,
            },
        }

        impl wyrm_state::State for Db {
            const SCHEMA: u32 = 5;
            type Op = Op;
            fn apply(&mut self, op: &Op) -> Result<(), String> {
                let Op::SetRole { role, grants } = op;
                self.roles.insert(role.clone(), grants.clone());
                Ok(())
            }
        }
    }

    fn old_store(name: &str, grants: Vec<(String, u8)>, snapshot: bool) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("wyrm-users-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let mut s = wyrm_state::Store::<old::Db>::open(&dir, b"users-key").unwrap();
        s.apply(old::Op::SetRole {
            role: "ops".into(),
            grants,
        })
        .unwrap();
        if snapshot {
            s.snapshot().unwrap();
        }
        dir
    }

    /// Review T4: grants were read with `filter_map(Perm::try_from(c).ok())`, so a restricting
    /// grant with an unknown code was dropped and the broad one after it decided. A SCHEMA 5
    /// snapshot with such a code opened, its grants kept as bare codes; now no form of that
    /// store opens.
    #[test]
    fn unknown_level_code_refuses_the_store() {
        let grants = vec![
            ("wy/s/downstream/plc/secret".to_string(), 9),
            ("wy/s/**".to_string(), Perm::Config.code()),
        ];
        for snapshot in [false, true] {
            let dir = old_store("unknown", grants.clone(), snapshot);
            let r = wyrm_state::Store::<UserDb>::open(&dir, b"users-key");
            let _ = std::fs::remove_dir_all(&dir);
            match r {
                Ok(s) => panic!("snapshot {snapshot}: opened {:?}", s.state().roles),
                Err(e) => assert!(e.to_string().contains("unknown level code 9"), "{e}"),
            }
        }
        // the API cannot make one: a record with the code does not decode
        let bytes = minicbor::to_vec(old::Op::SetRole {
            role: "ops".into(),
            grants,
        })
        .unwrap();
        assert!(minicbor::decode::<Op>(&bytes).is_err());
    }

    /// A store written before the grants were typed opens as it was, from its WAL and from
    /// its snapshot, and its restricting grant still decides first.
    #[test]
    fn grants_of_an_older_store_load_typed() {
        let grants = vec![
            ("wy/s/downstream/plc/secret".to_string(), Perm::None.code()),
            ("wy/s/**".to_string(), Perm::Config.code()),
        ];
        for snapshot in [false, true] {
            let dir = old_store("typed", grants.clone(), snapshot);
            let s = wyrm_state::Store::<UserDb>::open(&dir, b"users-key").unwrap();
            let ops = s.state().roles["ops"].clone();
            drop(s);
            let _ = std::fs::remove_dir_all(&dir);
            assert_eq!(
                ops,
                [
                    grant("wy/s/downstream/plc/secret", Perm::None),
                    grant("wy/s/**", Perm::Config)
                ],
                "snapshot {snapshot}"
            );
            let level =
                |k| wyrm_core::ptok::level_on(ops.iter().map(|g| (g.key.as_str(), g.perm)), k);
            assert_eq!(level("wy/s/downstream/plc/secret"), Perm::None);
            assert_eq!(level("wy/s/downstream/plc/t"), Perm::Config);
        }
        // the WAL record of a grant is the tuple's, byte for byte
        let g = grant("wy/s/**", Perm::Read);
        let tuple = ("wy/s/**".to_string(), Perm::Read.code());
        assert_eq!(
            minicbor::to_vec(&g).unwrap(),
            minicbor::to_vec(&tuple).unwrap()
        );
        // and a SCHEMA 5 snapshot body decodes as today's state (else the store would
        // rebuild from the WAL without a word), unless a code is unknown
        let snapshot = |grants: &[(String, u8)]| {
            let mut db = old::Db::default();
            db.roles.insert("ops".into(), grants.to_vec());
            postcard::to_stdvec(&db).unwrap()
        };
        let db: UserDb = postcard::from_bytes(&snapshot(&grants)).unwrap();
        assert_eq!(
            db.roles["ops"][0],
            grant("wy/s/downstream/plc/secret", Perm::None)
        );
        let unknown = [("wy/s/**".to_string(), 9)];
        assert!(postcard::from_bytes::<UserDb>(&snapshot(&unknown)).is_err());
    }

    #[test]
    fn ops_and_generations() {
        let mut db = UserDb::default();
        let add = Op::AddUser {
            name: "olena".into(),
            hash: "h".into(),
            roles: vec!["viewer".into()],
        };
        db.apply(&add).unwrap();
        assert!(db.apply(&add).is_err(), "duplicate");
        db.apply(&Op::SetPassword {
            name: "olena".into(),
            hash: "h2".into(),
        })
        .unwrap();
        db.apply(&Op::Disable {
            name: "olena".into(),
            disabled: true,
        })
        .unwrap();
        assert_eq!(db.users["olena"].gen, 3);
        db.apply(&Op::RemoveUser("olena".into())).unwrap();
        assert!(db.apply(&Op::RemoveUser("olena".into())).is_err());
        // a new user with the same name never reuses a generation
        db.apply(&add).unwrap();
        assert_eq!(db.users["olena"].gen, 4);
    }

    #[test]
    fn names_and_passwords() {
        assert!(valid_name("olena.k_1"));
        assert!(!valid_name("") && !valid_name("-x") && !valid_name("a/b"));
        assert!(check_password("short").is_err());
        let h = hash_password("correct horse").unwrap();
        assert!(h.starts_with("$argon2id$"));
        assert!(verify_password("correct horse", Some(&h)));
        assert!(!verify_password("wrong horse", Some(&h)));
        assert!(!verify_password("wyrm-gateway-dummy", None));
    }
}

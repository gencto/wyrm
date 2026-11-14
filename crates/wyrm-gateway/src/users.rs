//! User accounts, persisted with `wyrm-state` (the broker owns them, ADR
//! 0003). Passwords are argon2id PHC strings; hashing happens before the
//! operation is logged, so the WAL never sees a plaintext password.

use argon2::password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, SaltString};
use argon2::{Argon2, PasswordVerifier};
use minicbor::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

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
        /// `(key expression, Perm code)` in match order.
        #[n(1)]
        grants: Vec<(String, u8)>,
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

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct UserDb {
    pub users: BTreeMap<String, User>,
    /// Next generation; survives `RemoveUser`.
    pub next_gen: u64,
    /// Roles changed at runtime: role → `(key expression, Perm code)`.
    #[serde(default)]
    pub roles: BTreeMap<String, Vec<(String, u8)>>,
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
                if let Some((_, c)) = grants
                    .iter()
                    .find(|(_, c)| wyrm_core::Perm::try_from(*c).is_err())
                {
                    return Err(format!("bad level code {c}"));
                }
                // keys stored before spec 0.2.0 under their new names
                let grants = grants
                    .iter()
                    .map(|(k, c)| (wyrm_core::keyspace::renamed(k).into_owned(), *c))
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

    #[test]
    fn grant_keys_before_spec_0_2_replay_renamed() {
        let mut db = UserDb::default();
        db.apply(&Op::SetRole {
            role: "ops".into(),
            grants: vec![("wy/{site}/down/**".into(), 3), ("wy/**".into(), 1)],
        })
        .unwrap();
        assert_eq!(
            db.roles["ops"],
            [
                ("wy/{site}/downstream/**".to_string(), 3),
                ("wy/**".to_string(), 1)
            ]
        );
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

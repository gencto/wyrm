// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a uk locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'uk';

  static String m0(site) => "Доступ на ${site}";

  static String m1(n) => "${n} вх.";

  static String m2(n) => "${n} д тому";

  static String m3(n) => "${n} год тому";

  static String m4(n) => "${n} хв тому";

  static String m5(count) =>
      "${Intl.plural(count, one: 'Застосувати 1 зміну', few: 'Застосувати ${count} зміни', other: 'Застосувати ${count} змін')}";

  static String m6(count) => "Попросити адміністратора: ${count}";

  static String m7(n) => "просить приєднатися · ретранслює ${n}";

  static String m8(sites) => "просить ретранслювати: ${sites}";

  static String m9(code) => "відмовлено (${code})";

  static String m10(n) =>
      "${Intl.plural(n, one: '${n} блок', few: '${n} блоки', other: '${n} блоків')}";

  static String m11(brokers, devices) =>
      "${brokers} брокерів · ${devices} пристроїв";

  static String m12(driver) => "вбудований драйвер ${driver}";

  static String m13(site) => "підписано CA · ${site} CA";

  static String m14(n) =>
      "${Intl.plural(n, one: '1 блок стає', few: '${n} блоки стають', other: '${n} блоків стають')} одним блоком цього флоу. Дроти, що перетинають його межу, стають його входами та виходами.";

  static String m15(count) =>
      "${Intl.plural(count, zero: 'без дочірніх вузлів', one: '${count} дочірній вузол', few: '${count} дочірні вузли', other: '${count} дочірніх вузлів')}";

  static String m16(site) =>
      "${site} під’єднується до нього; там авторизують ${site}.";

  static String m17(size) => "data_dir ${size}";

  static String m18(id) => "Відкликати допуск ${id}?";

  static String m19(flow) =>
      "Чернетка «${flow}» замінить версію, що працює зараз.";

  static String m20(who) => "розгорнув ${who}";

  static String m21(device) =>
      "Працює на ${device}; брокер не може його запустити чи зупинити.";

  static String m22(id) => "Параметри ${id}";

  static String m23(time) =>
      "Решта подробиць у журналі брокера близько ${time}.";

  static String m24(field) =>
      "У формі поле ${field} позначено; виправте його та надішліть знову.";

  static String m25(role, site) =>
      "Ваша роль: ${role}. На ${site} нічого не змінено.";

  static String m26(call, key) => "${call} на ${key}";

  static String m27(type) => "studio · ${type}";

  static String m28(thing) => "розгорнути ${thing}";

  static String m29(thing) => "встановити ${thing}";

  static String m30(thing) => "отримати список ${thing}";

  static String m31(thing) => "увійти до ${thing}";

  static String m32(thing) => "відкрити ${thing}";

  static String m33(thing) => "прочитати ${thing}";

  static String m34(thing) => "вилучити ${thing}";

  static String m35(call, thing) => "виконати ${call} на ${thing}";

  static String m36(thing) => "зберегти ${thing}";

  static String m37(thing) => "запустити ${thing}";

  static String m38(step) => "завершити «${step}»";

  static String m39(thing) => "зупинити ${thing}";

  static String m40(thing) => "записати ${thing}";

  static String m41(thing) => "Розгортання ${thing}";

  static String m42(thing) => "Встановлення ${thing}";

  static String m43(thing) => "Список ${thing}";

  static String m44(thing) => "Вхід до ${thing}";

  static String m45(thing) => "Відкриття ${thing}";

  static String m46(thing) => "Читання ${thing}";

  static String m47(thing) => "Вилучення ${thing}";

  static String m48(call, thing) => "${call} на ${thing}";

  static String m49(thing) => "Збереження ${thing}";

  static String m50(thing) => "Запуск ${thing}";

  static String m51(thing) => "Зупинка ${thing}";

  static String m52(thing) => "Запис ${thing}";

  static String m53(call) => "${call}";

  static String m54(site) => "Брокер на ${site} не відповів.";

  static String m55(status) => "Брокер відповів ${status} без повідомлення.";

  static String m56(status, message) => "${status}: ${message}";

  static String m57(time) => "${time} (місцевий)";

  static String m58(doing, site) => "${doing}: помилка на ${site}";

  static String m59(doing) => "${doing}: помилка";

  static String m60(site, what) => "${site} зайнятий: ${what} не почато";

  static String m61(thing) => "${thing} більше немає";

  static String m62(thing) => "Історія ${thing} недоступна";

  static String m63(site) => "${site} не відповідає";

  static String m64(thing) => "Не вдалося прочитати ${thing}";

  static String m65(what) => "Ви не можете ${what}";

  static String m66(site) => "Живі значення з ${site} зупинилися";

  static String m67(what) => "Studio не вдалося ${what}";

  static String m68(thing, call) => "${thing} не підтримує ${call}";

  static String m69(seconds) => "Ще раз через ${seconds} с";

  static String m70(user, role) => "${user} (${role})";

  static String m71(s) => "кожні ${s} с";

  static String m72(reason) => "Нечитаний файл не вдалося відкласти: ${reason}";

  static String m73(name) =>
      "Нечитаний файл лишиться поруч із новим як ${name}. Ви знову додасте свої gateway та увійдете.";

  static String m74(panel) => "Studio не вдалося намалювати: ${panel}";

  static String m75(panel) => "Не вдалося намалювати: ${panel}";

  static String m76(when) => "уперше ${when}";

  static String m77(v) => "v${v} розгорнуто";

  static String m78(v) => "v${v} · помилка";

  static String m79(v) => "v${v} зупинено";

  static String m80(v) => "Версія ${v}";

  static String m81(site) => "Потоки на ${site}";

  static String m82(count) => "Блоків: ${count}";

  static String m83(label) => "Відкріпити «${label}» від блока";

  static String m84(address) => "з ${address}";

  static String m85(host, ms) => "${host} · відповів за ${ms} мс";

  static String m86(host) => "Немає відповіді від ${host}";

  static String m87(key) => "Перейти до ${key}";

  static String m88(id) => "Доступ для ${id}";

  static String m89(days) => "сирі дані ${days} д";

  static String m90(n) => "${n} рядів";

  static String m91(size) => "Історик ${size}";

  static String m92(id) => "Історія параметрів ${id}";

  static String m93(status) =>
      "Не вдалося прочитати історію: ${status}. Подробиці в «Проблемах».";

  static String m94(n) =>
      "${Intl.plural(n, one: '1 вхід', few: '${n} входи', other: '${n} входів')}";

  static String m95(name, broker) => "${name} встановлено на ${broker}.";

  static String m96(n) =>
      "${Intl.plural(n, zero: 'у цьому флоу немає екземплярів', one: '1 екземпляр у цьому флоу', few: '${n} екземпляри в цьому флоу', other: '${n} екземплярів у цьому флоу')} · зміна тут змінює всі";

  static String m97(count) => "Скопійовано ключів: ${count}";

  static String m98(lag) => "відставання ${lag}";

  static String m99(time) => "останнє читання ${time}";

  static String m100(n) =>
      "${Intl.plural(n, one: 'уже ${n} лінк', few: 'уже ${n} лінки', other: 'уже ${n} лінків')}";

  static String m101(n) =>
      "${Intl.plural(n, one: '${n} лінк', few: '${n} лінки', other: '${n} лінків')}";

  static String m102(site) =>
      "Запускає і стежить ${site}: вбудовані драйвери і встановлені пакети. Їх можна зупинити, змінити, оновити й видалити.";

  static String m103(site) => "Лінки на ${site}";

  static String m104(first, last) => "${first} і ${last}";

  static String m105(id) => "Журнал ${id}";

  static String m106(n) =>
      "${Intl.plural(n, one: 'його вживає 1 екземпляр', few: 'його вживають ${n} екземпляри', other: 'його вживають ${n} екземплярів')}";

  static String m107(n) => "бібліотека v${n}";

  static String m108(n) => "вжито: ${n}";

  static String m109(n) => "v${n}";

  static String m110(kind, count) => "${kind} · дій: ${count}";

  static String m111(count) =>
      "${Intl.plural(count, one: '… ще ${count} байт', few: '… ще ${count} байти', other: '… ще ${count} байтів')}";

  static String m112(count) => "Вибрано: ${count}";

  static String m113(level, have) => "Потрібно ${level} · у вас ${have}";

  static String m114(level) => "Потрібно ${level} · у вас є";

  static String m115(action) => "Цей вузол не має дії ${action}.";

  static String m116(param) => "Драйвер не має параметра ${param}.";

  static String m117(site) => "немає: ${site} — вершина";

  static String m118(site) => "Дерево покаже wy/${site}.";

  static String m119(site) => "Відкриваємо дерево сайту ${site}…";

  static String m120(name) => "пакет ${name}";

  static String m121(n) =>
      "${Intl.plural(n, one: '1 випадок', few: '${n} випадки', other: '${n} випадків')}";

  static String m122(n) =>
      "${Intl.plural(n, zero: 'без параметрів', one: '${n} параметр', few: '${n} параметри', other: '${n} параметрів')}";

  static String m123(rev) => "Параметри (ревізія ${rev}, JSON)";

  static String m124(detail) => "Це не JSON: ${detail}";

  static String m125(n) =>
      "${Intl.plural(n, one: '${n} точка', few: '${n} точки', other: '${n} точок')}";

  static String m126(n) =>
      "${Intl.plural(n, one: '1 порт', few: '${n} порти', other: '${n} портів')}";

  static String m127(step) => "${step} · пізніше";

  static String m128(site) => "Читання дерева сайту ${site}";

  static String m129(message) => "Чернетка не запускається: ${message}";

  static String m130(count) =>
      "${Intl.plural(count, one: '1 проблема', few: '${count} проблеми', many: '${count} проблем', other: '${count} проблеми')}";

  static String m131(name) => "${name} встановлено";

  static String m132(name) => "Встановлення ${name}…";

  static String m133(sites) => "досягає ${sites}";

  static String m134(status) =>
      "Не вдалося прочитати значення: ${status}. Подробиці в «Проблемах».";

  static String m135(field) =>
      "Цей брокер не може прив\'язати ${field} (його рушій флоу старший за ADR 0040)";

  static String m136(field) => "${field} не має входу: введіть значення";

  static String m137(from, to) => "${from} не підходить до ${to}";

  static String m138(cn) => "Відхилити ${cn}?";

  static String m139(n) =>
      "${Intl.plural(n, one: 'ретранслює ${n} сайт', few: 'ретранслює ${n} сайти', other: 'ретранслює ${n} сайтів')}";

  static String m140(id) => "Видалити ${id}?";

  static String m141(name) => "Видалити ${name}?";

  static String m142(action) => "Результат · ${action}";

  static String m143(what) => "повертає ${what}";

  static String m144(audit) =>
      "Кожен запис перевіряє лінк і фіксує в ${audit}. Значення зʼявляється лише після зворотного читання.";

  static String m145(rev) => "Ревізія ${rev}";

  static String m146(rev) => "Ревізія ${rev} · діє";

  static String m147(site, user, role, level) =>
      "Сайт ${site} · застосовується з вашими правами: ${user}, ${role} (${level})";

  static String m148(role, site) => "${role} на ${site}";

  static String m149(rev) => "Повернути ревізію ${rev}?";

  static String m150(n) =>
      "${Intl.plural(n, one: '${n} рядок', few: '${n} рядки', other: '${n} рядків')}";

  static String m151(user) =>
      "Виконується як ${user}. Нічого більше в дереві не змінюється, якщо результат не використати.";

  static String m152(site) => "Працює на ${site}";

  static String m153(name) => "${name}";

  static String m154(level) => "Рівень журналу ${level}";

  static String m155(site) => "Сайти навколо ${site}";

  static String m156(site) =>
      "До чого під’єднаний ${site} і що під’єднано до нього: брокери вище й нижче, платформи, куди він надсилає, і пристрої, чиї лінки працюють поза брокером.";

  static String m157(count) =>
      "${Intl.plural(count, one: '${count} байт', few: '${count} байти', other: '${count} байтів')}";

  static String m158(count) =>
      "${Intl.plural(count, one: '${count} символ', few: '${count} символи', other: '${count} символів')}";

  static String m159(count) =>
      "${Intl.plural(count, one: '${count} елемент', few: '${count} елементи', other: '${count} елементів')}";

  static String m160(count) =>
      "${Intl.plural(count, one: '${count} ключ', few: '${count} ключі', other: '${count} ключів')}";

  static String m161(count) =>
      "${Intl.plural(count, one: '${count} рядок', few: '${count} рядки', other: '${count} рядків')}";

  static String m162(count) =>
      "${Intl.plural(count, zero: 'Немає підготовлених змін', one: '${count} підготовлена зміна', few: '${count} підготовлені зміни', other: '${count} підготовлених змін')}";

  static String m163(was) => "підготовлено · було ${was}";

  static String m164(host) => "Резерв: ${host}";

  static String m165(n, total) => "Крок ${n} з ${total}";

  static String m166(host) => "З’єднання з ${host}";

  static String m167(version, os) => "${version} (${os})";

  static String m168(version, language) => "Studio ${version} · ${language}";

  static String m169(n) => "Відмов ACL побільшало на ${n}";

  static String m170(from) =>
      "acl_denied дорівнював ${from}, коли цей екран показували востаннє";

  static String m171(n) => "Резерв відстає на ${n} записів";

  static String m172(n) => "Відкладено розгалужень після розколу: ${n}";

  static String m173(site) => "${site} чекає на Authorize";

  static String m174(n) => "Нижчий брокер, що ретранслює сайтів: ${n}";

  static String m175(id) =>
      "sys/links/${id}/state має стан failed; причина в його журналі";

  static String m176(id) => "${id} не працює";

  static String m177(cn) => "${cn} чекає в карантині";

  static String m178(cn) => "Невідомий сертифікат CN ${cn}";

  static String m179(cn, t) => "Невідомий сертифікат CN ${cn} від ${t}";

  static String m180(size) =>
      "Усе, чим володіє брокер, лежить у його `data_dir` (тут ${size}). Studio не робить резервних копій: вони містять ключі сайту, їх роблять на хості. Кроки, готові до копіювання:";

  static String m181(n) =>
      "Наборів записів, відкладених після того, як обидва брокери були активні (усунений розкол): ${n}. Запис аудиту `standby_forked` каже які.";

  static String m182(n) =>
      "Записів реєстру, яких ще немає на резерві: ${n}. Перемикання зараз їх втратить.";

  static String m183(n) => "Очистити від’єднані лінки (${n})…";

  static String m184(ids) =>
      "${ids}\n\nЇхні id вибувають і більше не можуть бути використані.";

  static String m185(n) => "Очистити від’єднані лінки: ${n}…";

  static String m186(ids) => "Вилучено: ${ids}";

  static String m187(title) => "Копіювати: ${title}";

  static String m188(url) => "Посилання на посібник скопійовано: ${url}";

  static String m189(id) => "лінк: ${id}";

  static String m190(n) => "Скопійовано рядків: ${n}";

  static String m191(path) => "Збережено ${path}";

  static String m192(n) =>
      "Рядків із кільця брокера: ${n} · новіші зверху · `sys/~act/get_log`";

  static String m193(t) => "запущено ${t}";

  static String m194(n) => "Потребує уваги · ${n}";

  static String m195(standby) =>
      "2. У `wyrmd.json5` на обох хостах: `${standby}` і `peers.listen`; радимо `arbiter` оренди на третьому хості.";

  static String m196(t) => "${t} · зараз";

  static String m197(n) => "з ${n}";

  static String m198(name) =>
      "Файл ${name}. Файл .cbor надсилається як є; файл JSON спершу кодується.";

  static String m199(name) => "Профіль ${name} додано";

  static String m200(name) => "Профіль ${name} вилучено";

  static String m201(reason) =>
      "Цей брокер не віддає перелік профілів через шлюз (${reason}). Профіль усе одно можна додати; брокер віддаватиме його як pub/<name>.";

  static String m202(name) => "Вилучити профіль ${name}";

  static String m203(name) =>
      "Брокер перестає віддавати pub/${name} і записує це в журнал аудиту (profile_remove).";

  static String m204(cn) => "зовнішній · CN ${cn}";

  static String m205(size) => "історія ${size} · відкрити Історію";

  static String m206(id) => "${id} не працює · відкрити Лінки";

  static String m207(site) => "${site} · відкрити Сайти";

  static String m208(cn) => "${cn} чекає · відкрити Карантин";

  static String m209(measure, from, to) =>
      "${measure} на вхід і вихід за секунду від ${from} до ${to}";

  static String m210(level) => "потрібно ${level}";

  static String m211(agent) => "Кожна задача — вузол: ${agent}/tasks/<id>";

  static String m212(site) => "TLS · сертифікат CA сайту ${site}";

  static String m213(seconds) => "зникне через ${seconds} с";

  static String m214(site) => "лишається, доки ${site} не повернеться";

  static String m215(site) => "Дерево · ${site}";

  static String m216(unit) => "адреса ${unit}";

  static String m217(d) => "працює ${d}";

  static String m218(v) => "Версія ${v} · розгорнута";

  static String m219(site) => "через ${site}";

  static String m220(keys) => "${keys} зберігає · Esc скасовує";

  static String m221(n, who) => "${n} чекають на допуск: ${who}";

  static String m222(value) => "було ${value}";

  static String m223(n) => "Групи спостереження · ${n}";

  static String m224(user) => "Вітаємо, ${user}";

  static String m225(value) => "запустив би на ${value}";

  static String m226(value) => "надіслав би ${value}";

  static String m227(value) => "записав би ${value}";

  static String m228(level) => "Щоб увімкнути, потрібен рівень ${level}";

  static String m229(site) => "wyrmd на ${site}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "_locale": MessageLookupByLibrary.simpleMessage("uk"),
    "aCustomPackage": MessageLookupByLibrary.simpleMessage("Власний пакет"),
    "acceptFirst": MessageLookupByLibrary.simpleMessage(
      "Спершу прийміть запитані права.",
    ),
    "acceptRequestedRights": MessageLookupByLibrary.simpleMessage(
      "Прийняти запитані права",
    ),
    "accepted": MessageLookupByLibrary.simpleMessage("прийнято"),
    "accessOn": m0,
    "accessSubtitle": MessageLookupByLibrary.simpleMessage(
      "Хто може входити в цей gateway, що доступно кожній ролі і що було зроблено.",
    ),
    "actComesWithWyrmd": MessageLookupByLibrary.simpleMessage(
      "Входить до wyrmd",
    ),
    "actComesWithWyrmdNote": MessageLookupByLibrary.simpleMessage(
      "Вбудований драйвер оновлюється разом із брокером.",
    ),
    "actDeauthorize": MessageLookupByLibrary.simpleMessage("Відкликати допуск"),
    "actDeauthorizeNote": MessageLookupByLibrary.simpleMessage(
      "Заблокувати зараз: права забрано, наступне з’єднання чекатиме в карантині. Дерево лишається.",
    ),
    "actEditParams": MessageLookupByLibrary.simpleMessage("Змінити параметри"),
    "actEditParamsNote": MessageLookupByLibrary.simpleMessage(
      "Параметри лінка. Зберігаються як нова ревізія.",
    ),
    "actGrant": MessageLookupByLibrary.simpleMessage("Надати доступ"),
    "actGrantNote": MessageLookupByLibrary.simpleMessage(
      "Читання або запис поза власною гілкою.",
    ),
    "actGrants": MessageLookupByLibrary.simpleMessage("Доступи"),
    "actGrantsNote": MessageLookupByLibrary.simpleMessage(
      "Лише власна гілка. Додайте читання або запис деінде.",
    ),
    "actParamsHistory": MessageLookupByLibrary.simpleMessage(
      "Історія параметрів",
    ),
    "actParamsHistoryNote": MessageLookupByLibrary.simpleMessage(
      "Ревізії параметрів; поверніться до будь-якої.",
    ),
    "actRemoveForGood": MessageLookupByLibrary.simpleMessage(
      "Видалити назавжди",
    ),
    "actRemoveForGoodNote": MessageLookupByLibrary.simpleMessage(
      "Вилучити id: цей сертифікат більше не отримає прав. Новому пристрою потрібен новий сертифікат.",
    ),
    "actRemoveLink": MessageLookupByLibrary.simpleMessage("Видалити лінк"),
    "actRemoveLinkNote": MessageLookupByLibrary.simpleMessage(
      "Зупиняє його і видаляє його дерево.",
    ),
    "actSecrets": MessageLookupByLibrary.simpleMessage("Секрети"),
    "actSecretsNote": MessageLookupByLibrary.simpleMessage(
      "Паролі й ключі, запечатані; більше не показуються.",
    ),
    "actStart": MessageLookupByLibrary.simpleMessage("Запустити"),
    "actStartNote": MessageLookupByLibrary.simpleMessage(
      "Запустити знову з останніми параметрами.",
    ),
    "actStartStopRestart": MessageLookupByLibrary.simpleMessage(
      "Запуск, зупинка, перезапуск",
    ),
    "actStop": MessageLookupByLibrary.simpleMessage("Зупинити"),
    "actStopNote": MessageLookupByLibrary.simpleMessage(
      "Лишається встановленим; його точки стають bad до запуску.",
    ),
    "actUpgrade": MessageLookupByLibrary.simpleMessage("Оновити"),
    "actUpgradeNote": MessageLookupByLibrary.simpleMessage(
      "Встановити новішу версію пакета.",
    ),
    "actUpgradeParamsLog": MessageLookupByLibrary.simpleMessage(
      "Оновлення, параметри, журнал",
    ),
    "actViewLog": MessageLookupByLibrary.simpleMessage("Журнал"),
    "actViewLogNote": MessageLookupByLibrary.simpleMessage(
      "Останні рядки і власний рівень журналу.",
    ),
    "actionInputs": m1,
    "addALink": MessageLookupByLibrary.simpleMessage("Додати лінк"),
    "addAgent": MessageLookupByLibrary.simpleMessage("Додати link агента"),
    "addAnother": MessageLookupByLibrary.simpleMessage("Додати ще"),
    "addGrant": MessageLookupByLibrary.simpleMessage("Додати дозвіл"),
    "addInput": MessageLookupByLibrary.simpleMessage("Додати вхід"),
    "addPair": MessageLookupByLibrary.simpleMessage("Додати випадок"),
    "addPoint": MessageLookupByLibrary.simpleMessage("Додати точку"),
    "addPort": MessageLookupByLibrary.simpleMessage("Додати порт"),
    "addStandby": MessageLookupByLibrary.simpleMessage(
      "Додати резервний gateway",
    ),
    "addUser": MessageLookupByLibrary.simpleMessage("Додати користувача"),
    "addWatchPath": MessageLookupByLibrary.simpleMessage("Додати точку"),
    "addWatchPathNote": MessageLookupByLibrary.simpleMessage(
      "Записувати ще одну точку (ключ у downstream, dataflows або storage).",
    ),
    "adminsOnly": MessageLookupByLibrary.simpleMessage(
      "Користувачами керують адміністратори gateway.",
    ),
    "agoDays": m2,
    "agoHours": m3,
    "agoMinutes": m4,
    "agoNow": MessageLookupByLibrary.simpleMessage("щойно"),
    "allowAllLinks": MessageLookupByLibrary.simpleMessage(
      "Допускати всі лінки",
    ),
    "allowAllLinksNote": MessageLookupByLibrary.simpleMessage(
      "Кожен новий CN цього CA одразу стає лінком, без схвалення. Витеклий сертифікат теж пройде.",
    ),
    "andWord": MessageLookupByLibrary.simpleMessage("і"),
    "answerBroker": MessageLookupByLibrary.simpleMessage("Брокер"),
    "answerFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "answerLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "answerName": MessageLookupByLibrary.simpleMessage("Назва"),
    "answerRights": MessageLookupByLibrary.simpleMessage("Права"),
    "answerRuns": MessageLookupByLibrary.simpleMessage("Працює"),
    "appTitle": MessageLookupByLibrary.simpleMessage("WYRM Studio"),
    "apply": MessageLookupByLibrary.simpleMessage("Застосувати"),
    "applyChanges": m5,
    "applyProfile": MessageLookupByLibrary.simpleMessage("Застосувати профіль"),
    "approve": MessageLookupByLibrary.simpleMessage("Схвалити"),
    "approveBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення допускає його як брокер нижче з указаними ретрансляціями. Спершу порівняйте ключ із його sys/upstream/<цей сайт>/key.",
    ),
    "approveLinkNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення робить його зовнішнім лінком із власною гілкою і токеном; скопіюйте токен на пристрій. Роутер перезавантажується приблизно на секунду. Відхилення відмовляє цьому CN надалі.",
    ),
    "approveReasonNote": MessageLookupByLibrary.simpleMessage(
      "Для схвалення gateway має підписати кроки за тебе (docs/studio.md §10 п. 1). Поки що схвалюй через wyrm-agent.",
    ),
    "askAdminFor": m6,
    "askAdminReason": MessageLookupByLibrary.simpleMessage(
      "Брокер ще не має виклику, щоб надіслати запит адміністратору.",
    ),
    "askButton": MessageLookupByLibrary.simpleMessage("Запитати"),
    "askHint": MessageLookupByLibrary.simpleMessage(
      "Опиши зміну або постав питання про мережу (Cmd+Enter)",
    ),
    "asksToJoin": MessageLookupByLibrary.simpleMessage("просить приєднатися"),
    "asksToJoinRelays": m7,
    "asksToRelay": m8,
    "auditDone": MessageLookupByLibrary.simpleMessage("виконано"),
    "auditNeeds": MessageLookupByLibrary.simpleMessage(
      "Аудит потребує рівня config на sys/audit.",
    ),
    "auditRefused": m9,
    "back": MessageLookupByLibrary.simpleMessage("Назад"),
    "backToLinks": MessageLookupByLibrary.simpleMessage("До лінків"),
    "bindHint": MessageLookupByLibrary.simpleMessage(
      "Перетягніть сюди вихід, щоб зв’язати",
    ),
    "block": MessageLookupByLibrary.simpleMessage("Блок"),
    "blockForm": MessageLookupByLibrary.simpleMessage("Форма"),
    "blockInputs": MessageLookupByLibrary.simpleMessage("Входи"),
    "blockOutputs": MessageLookupByLibrary.simpleMessage("Виходи"),
    "blocksCount": m10,
    "boundMark": MessageLookupByLibrary.simpleMessage("зв’язано"),
    "branchOrTag": MessageLookupByLibrary.simpleMessage("гілка або тег"),
    "bringOne": MessageLookupByLibrary.simpleMessage(
      "Оберіть файл або вкажіть, де пакет.",
    ),
    "brokerLog": MessageLookupByLibrary.simpleMessage("Журнал"),
    "brokerRefused": MessageLookupByLibrary.simpleMessage(
      "Брокер відхилив зміну; наступні не застосовано.",
    ),
    "brokerSays": MessageLookupByLibrary.simpleMessage("Брокер каже"),
    "brokerWaiting": MessageLookupByLibrary.simpleMessage("Брокер чекає"),
    "brokersDevices": m11,
    "builtIn": MessageLookupByLibrary.simpleMessage("вбудований"),
    "builtInDriver": m12,
    "builtInSummary": MessageLookupByLibrary.simpleMessage(
      "Вбудований у wyrmd · нічого не завантажується",
    ),
    "caSigned": m13,
    "canDoNothing": MessageLookupByLibrary.simpleMessage(
      "нічого: ні читання, ні запису",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Скасувати"),
    "cancelTask": MessageLookupByLibrary.simpleMessage("Скасувати задачу"),
    "cannotReachGateway": MessageLookupByLibrary.simpleMessage(
      "Не вдалося з’єднатися з gateway",
    ),
    "cantReachGateway": MessageLookupByLibrary.simpleMessage(
      "Gateway не відповідає",
    ),
    "catalogNote": MessageLookupByLibrary.simpleMessage(
      "Вбудований: у wyrmd, нічого не завантажується. Пакет: з індексу packages.repository, SHA-256 перевіряється; брокер показує лише пакети, які може встановити.",
    ),
    "cbBadName": MessageLookupByLibrary.simpleMessage(
      "Назва має лише літери, цифри та _",
    ),
    "cbBadPort": MessageLookupByLibrary.simpleMessage(
      "Назва порту має лише літери, цифри та _",
    ),
    "cbCreate": MessageLookupByLibrary.simpleMessage("Створити"),
    "cbDefault": MessageLookupByLibrary.simpleMessage("за замовчуванням"),
    "cbDescription": MessageLookupByLibrary.simpleMessage("Опис"),
    "cbDuplicate": MessageLookupByLibrary.simpleMessage(
      "Два порти мають однакову назву",
    ),
    "cbInputs": MessageLookupByLibrary.simpleMessage("Входи"),
    "cbLimit": MessageLookupByLibrary.simpleMessage(
      "Не більше 64 блоків, 64 входів і 64 виходів у кожному",
    ),
    "cbName": MessageLookupByLibrary.simpleMessage("Назва"),
    "cbNone": MessageLookupByLibrary.simpleMessage("немає"),
    "cbNote": m14,
    "cbOutputs": MessageLookupByLibrary.simpleMessage("Виходи"),
    "cbTaken": MessageLookupByLibrary.simpleMessage(
      "Цей флоу вже має блок з такою назвою",
    ),
    "cbTitle": MessageLookupByLibrary.simpleMessage("Створити власний блок"),
    "cfgApiKey": MessageLookupByLibrary.simpleMessage("Секрет API-ключа"),
    "cfgApproval": MessageLookupByLibrary.simpleMessage("Схвалення для"),
    "cfgBudget": MessageLookupByLibrary.simpleMessage("Токенів на день"),
    "cfgModel": MessageLookupByLibrary.simpleMessage("Модель"),
    "cfgPrefixes": MessageLookupByLibrary.simpleMessage("Може змінювати"),
    "changeAnswers": MessageLookupByLibrary.simpleMessage("Змінити відповіді"),
    "checkFailed": MessageLookupByLibrary.simpleMessage(
      "Пакет не пройшов перевірку: принесіть інший.",
    ),
    "checkYourConnection": MessageLookupByLibrary.simpleMessage(
      "Перевірте з’єднання та спробуйте ще раз.",
    ),
    "checkedHere": MessageLookupByLibrary.simpleMessage(
      "Перевірено тут; брокер перевірить ще раз перед встановленням.",
    ),
    "checkingGateway": MessageLookupByLibrary.simpleMessage(
      "Перевірка gateway",
    ),
    "childCount": m15,
    "childrenNote": MessageLookupByLibrary.simpleMessage(
      "Вибери рядок: вузол відкривається в дереві, значення — в інспекторі.",
    ),
    "chooseWasm": MessageLookupByLibrary.simpleMessage(
      "Оберіть компонент .wasm",
    ),
    "chooseZip": MessageLookupByLibrary.simpleMessage("Оберіть пакет .zip"),
    "clearConns": MessageLookupByLibrary.simpleMessage(
      "Прибрати від’єднані лінки",
    ),
    "clearConnsNote": MessageLookupByLibrary.simpleMessage(
      "Видаляє зовнішні лінки, які не під’єднані; їхні id вилучаються.",
    ),
    "clearSelection": MessageLookupByLibrary.simpleMessage("Очистити"),
    "closeLabel": MessageLookupByLibrary.simpleMessage("Закрити"),
    "colCertificate": MessageLookupByLibrary.simpleMessage("Сертифікат"),
    "colDeployedBy": MessageLookupByLibrary.simpleMessage("Хто розгорнув"),
    "colFlow": MessageLookupByLibrary.simpleMessage("Потік"),
    "colFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "colKey": MessageLookupByLibrary.simpleMessage("Ключ"),
    "colKind": MessageLookupByLibrary.simpleMessage("Вид"),
    "colLevel": MessageLookupByLibrary.simpleMessage("Рівень"),
    "colLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "colLinkDevice": MessageLookupByLibrary.simpleMessage("Лінк · пристрій"),
    "colMode": MessageLookupByLibrary.simpleMessage("Режим"),
    "colName": MessageLookupByLibrary.simpleMessage("Назва"),
    "colOp": MessageLookupByLibrary.simpleMessage("Що"),
    "colPoint": MessageLookupByLibrary.simpleMessage("Точка"),
    "colPoll": MessageLookupByLibrary.simpleMessage("Опитування"),
    "colQuality": MessageLookupByLibrary.simpleMessage("Якість"),
    "colReadsWrites": MessageLookupByLibrary.simpleMessage("Читає → пише"),
    "colRegister": MessageLookupByLibrary.simpleMessage("Регістр"),
    "colResult": MessageLookupByLibrary.simpleMessage("Результат"),
    "colRole": MessageLookupByLibrary.simpleMessage("Роль"),
    "colRoles": MessageLookupByLibrary.simpleMessage("Ролі"),
    "colRows": MessageLookupByLibrary.simpleMessage("Рядків показано"),
    "colRunsAs": MessageLookupByLibrary.simpleMessage("Працює як"),
    "colSource": MessageLookupByLibrary.simpleMessage("Звідки"),
    "colState": MessageLookupByLibrary.simpleMessage("Стан"),
    "colTime": MessageLookupByLibrary.simpleMessage("Час"),
    "colType": MessageLookupByLibrary.simpleMessage("Тип"),
    "colUnit": MessageLookupByLibrary.simpleMessage("Одиниця"),
    "colUser": MessageLookupByLibrary.simpleMessage("Користувач"),
    "colValue": MessageLookupByLibrary.simpleMessage("Значення"),
    "colVersionSource": MessageLookupByLibrary.simpleMessage(
      "Версія · джерело",
    ),
    "colWatch": MessageLookupByLibrary.simpleMessage("Спостереження"),
    "colWho": MessageLookupByLibrary.simpleMessage("Хто"),
    "colWhyHere": MessageLookupByLibrary.simpleMessage("Чому тут"),
    "colWrite": MessageLookupByLibrary.simpleMessage("Запис"),
    "collecting": MessageLookupByLibrary.simpleMessage("Збираю значення…"),
    "configAllowed": MessageLookupByLibrary.simpleMessage(
      "config дозволено для цього верхнього",
    ),
    "configureStaged": MessageLookupByLibrary.simpleMessage(
      "Налаштування · підготовлено",
    ),
    "configureStagedNote": MessageLookupByLibrary.simpleMessage(
      "Готуються разом з іншими змінами; застосовуються в перегляді.",
    ),
    "connect": MessageLookupByLibrary.simpleMessage("Під’єднати"),
    "connectNote": m16,
    "connectUpstream": MessageLookupByLibrary.simpleMessage(
      "Під’єднати до верхнього",
    ),
    "connected": MessageLookupByLibrary.simpleMessage("під’єднано"),
    "continueLabel": MessageLookupByLibrary.simpleMessage("Далі"),
    "controlPlane": MessageLookupByLibrary.simpleMessage("Площина керування"),
    "copiedValue": MessageLookupByLibrary.simpleMessage("Скопійовано"),
    "copyKey": MessageLookupByLibrary.simpleMessage("Копіювати ключ"),
    "copyKeys": MessageLookupByLibrary.simpleMessage("Копіювати ключі"),
    "copyValue": MessageLookupByLibrary.simpleMessage("Копіювати"),
    "couldNotConnectToInternet": MessageLookupByLibrary.simpleMessage(
      "Не вдалося підключитися до інтернету.",
    ),
    "customPackage": MessageLookupByLibrary.simpleMessage("Власний пакет"),
    "customPackageNote": MessageLookupByLibrary.simpleMessage(
      "Архів пакета, який ви приносите: zip, URL, Git-репозиторій або один .wasm. Перевіряється перед встановленням.",
    ),
    "darkTheme": MessageLookupByLibrary.simpleMessage("Темна тема"),
    "dataDir": m17,
    "dataflow": MessageLookupByLibrary.simpleMessage("Потік даних"),
    "deauthorizeBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Його права тут забрано зараз, наступне з’єднання чекатиме в карантині. Його сайти лишаються під ним.",
    ),
    "deauthorizeTitle": m18,
    "decideInLinks": MessageLookupByLibrary.simpleMessage("Вирішити в Лінках"),
    "decideInLinksNote": MessageLookupByLibrary.simpleMessage(
      "Лінк у карантині схвалюють або відхиляють у Лінках › Карантин.",
    ),
    "decideInSites": MessageLookupByLibrary.simpleMessage("вирішіть у Сайтах"),
    "deploy": MessageLookupByLibrary.simpleMessage("Розгорнути"),
    "deployAskMessage": m19,
    "deployAskTitle": MessageLookupByLibrary.simpleMessage(
      "Розгорнути цей потік?",
    ),
    "deployInside": MessageLookupByLibrary.simpleMessage(
      "Щоб розгорнути, повернися до флоу",
    ),
    "deployedByWho": m20,
    "deploying": MessageLookupByLibrary.simpleMessage("Розгортання…"),
    "designGallery": MessageLookupByLibrary.simpleMessage("Галерея дизайну"),
    "designGalleryNote": MessageLookupByLibrary.simpleMessage(
      "Усі частини дизайн-системи (лише для розробки).",
    ),
    "disableUser": MessageLookupByLibrary.simpleMessage("Вимкнути"),
    "disableUserNote": MessageLookupByLibrary.simpleMessage(
      "Вимкнений користувач не може увійти; ролі лишаються.",
    ),
    "discard": MessageLookupByLibrary.simpleMessage("Скасувати все"),
    "discardAll": MessageLookupByLibrary.simpleMessage("Скасувати все"),
    "doneNote": MessageLookupByLibrary.simpleMessage(
      "Задачу виконано. План і журнал лишаються в її записі.",
    ),
    "doneOnTheDevice": m21,
    "doneOnTheDeviceUpgrade": MessageLookupByLibrary.simpleMessage(
      "Хто керує пристроєм, той і оновлює його; він перепідключиться з тим самим сертифікатом.",
    ),
    "downstream": MessageLookupByLibrary.simpleMessage("нижче"),
    "downstreamBroker": MessageLookupByLibrary.simpleMessage("Брокер нижче"),
    "downstreamBrokerQuic": MessageLookupByLibrary.simpleMessage(
      "брокер нижче · через quic",
    ),
    "draftSaved": MessageLookupByLibrary.simpleMessage("Чернетку збережено"),
    "draftValid": MessageLookupByLibrary.simpleMessage(
      "Чернетка · правильна, не розгорнута",
    ),
    "dropRead": MessageLookupByLibrary.simpleMessage("Читати"),
    "dropWrite": MessageLookupByLibrary.simpleMessage("Писати"),
    "editDataflow": MessageLookupByLibrary.simpleMessage("Редагувати потік"),
    "editDataflowNote": MessageLookupByLibrary.simpleMessage(
      "Відкрити в редакторі; нічого не змінюється до розгортання.",
    ),
    "editGroup": MessageLookupByLibrary.simpleMessage("Змінити групу"),
    "editGroupNote": MessageLookupByLibrary.simpleMessage(
      "Як і як часто записуються точки.",
    ),
    "editParamsNote": MessageLookupByLibrary.simpleMessage(
      "«Підготувати» застосовується з іншими змінами; лінк перезапуститься з новою ревізією.",
    ),
    "editParamsOf": m22,
    "enableUser": MessageLookupByLibrary.simpleMessage("Увімкнути"),
    "errAdviceBroker": m23,
    "errAdviceBrokerSaid": MessageLookupByLibrary.simpleMessage(
      "Виклик дійшов до брокера, і він відмовив. Перевірте те, що він назвав вище.",
    ),
    "errAdviceBusy": MessageLookupByLibrary.simpleMessage(
      "Зачекайте трохи та спробуйте ще раз.",
    ),
    "errAdviceBusyAuto": MessageLookupByLibrary.simpleMessage(
      "Studio спробує ще раз сама, коли брокер буде готовий.",
    ),
    "errAdviceGone": MessageLookupByLibrary.simpleMessage(
      "Хтось вилучив або перейменував це після завантаження екрана. Оновіть, щоб побачити поточний стан.",
    ),
    "errAdviceInput": MessageLookupByLibrary.simpleMessage(
      "Поверніться до форми, виправте значення та надішліть знову.",
    ),
    "errAdviceInputField": m24,
    "errAdviceReach": MessageLookupByLibrary.simpleMessage(
      "Спробуйте ще раз; якщо помилка повторюється, перевірте стан лінка в Links.",
    ),
    "errAdviceReachLogin": MessageLookupByLibrary.simpleMessage(
      "Увійдіть знову: Studio не має сесії з gateway.",
    ),
    "errAdviceReport": MessageLookupByLibrary.simpleMessage(
      "Скопіюйте звіт і надішліть нам: він не містить значень і паролів.",
    ),
    "errAdviceRights": MessageLookupByLibrary.simpleMessage(
      "Попросіть адміністратора надати право або зробити це.",
    ),
    "errAdviceRightsRole": m25,
    "errAdviceStudio": MessageLookupByLibrary.simpleMessage(
      "Спробуйте ще раз; якщо повторюється, перезапустіть Studio.",
    ),
    "errAdviceUnsupported": MessageLookupByLibrary.simpleMessage(
      "Цей брокер або лінк не має такого виклику; можливо, він старіший, ніж очікує Studio.",
    ),
    "errBackToForm": MessageLookupByLibrary.simpleMessage("Назад до форми"),
    "errCallOn": m26,
    "errChipStudio": m27,
    "errCopied": MessageLookupByLibrary.simpleMessage("Скопійовано"),
    "errCopyDetails": MessageLookupByLibrary.simpleMessage(
      "Копіювати подробиці",
    ),
    "errCopyReport": MessageLookupByLibrary.simpleMessage("Копіювати звіт"),
    "errDetails": MessageLookupByLibrary.simpleMessage("Подробиці"),
    "errDetailsCopied": MessageLookupByLibrary.simpleMessage(
      "Подробиці в буфері обміну.",
    ),
    "errDoDeploy": m28,
    "errDoInstall": m29,
    "errDoList": m30,
    "errDoLogIn": m31,
    "errDoOpen": m32,
    "errDoRead": m33,
    "errDoRemove": m34,
    "errDoRun": m35,
    "errDoSave": m36,
    "errDoStart": m37,
    "errDoStep": m38,
    "errDoStop": m39,
    "errDoWrite": m40,
    "errDoingDeploy": m41,
    "errDoingInstall": m42,
    "errDoingList": m43,
    "errDoingLogIn": m44,
    "errDoingOpen": m45,
    "errDoingRead": m46,
    "errDoingRemove": m47,
    "errDoingRun": m48,
    "errDoingSave": m49,
    "errDoingStart": m50,
    "errDoingStop": m51,
    "errDoingWrite": m52,
    "errFaultMessage": MessageLookupByLibrary.simpleMessage(
      "Тут стався збій у Studio. Це помилка Studio, а не брокера; більше нічого не надіслано.",
    ),
    "errNounDeploy": MessageLookupByLibrary.simpleMessage("розгортання"),
    "errNounInstall": MessageLookupByLibrary.simpleMessage("встановлення"),
    "errNounList": MessageLookupByLibrary.simpleMessage("список"),
    "errNounLogIn": MessageLookupByLibrary.simpleMessage("вхід"),
    "errNounOpen": MessageLookupByLibrary.simpleMessage("відкриття"),
    "errNounRead": MessageLookupByLibrary.simpleMessage("читання"),
    "errNounRemove": MessageLookupByLibrary.simpleMessage("вилучення"),
    "errNounRun": m53,
    "errNounSave": MessageLookupByLibrary.simpleMessage("збереження"),
    "errNounStart": MessageLookupByLibrary.simpleMessage("запуск"),
    "errNounStop": MessageLookupByLibrary.simpleMessage("зупинка"),
    "errNounWrite": MessageLookupByLibrary.simpleMessage("запис"),
    "errOpenLog": MessageLookupByLibrary.simpleMessage("Відкрити журнал"),
    "errRefresh": MessageLookupByLibrary.simpleMessage("Оновити"),
    "errReportCopied": MessageLookupByLibrary.simpleMessage(
      "Звіт у буфері обміну.",
    ),
    "errReportNote": MessageLookupByLibrary.simpleMessage(
      "трасування стека є лише у скопійованому звіті",
    ),
    "errRowAs": MessageLookupByLibrary.simpleMessage("Від імені"),
    "errRowCall": MessageLookupByLibrary.simpleMessage("Виклик"),
    "errRowError": MessageLookupByLibrary.simpleMessage("Помилка"),
    "errRowGateway": MessageLookupByLibrary.simpleMessage("Gateway"),
    "errRowIn": MessageLookupByLibrary.simpleMessage("Де"),
    "errRowReport": MessageLookupByLibrary.simpleMessage("Звіт"),
    "errRowScreen": MessageLookupByLibrary.simpleMessage("Екран"),
    "errRowSite": MessageLookupByLibrary.simpleMessage("Сайт"),
    "errRowStatus": MessageLookupByLibrary.simpleMessage("Статус"),
    "errRowStudio": MessageLookupByLibrary.simpleMessage("Studio"),
    "errRowTime": MessageLookupByLibrary.simpleMessage("Час"),
    "errSaidBroker": MessageLookupByLibrary.simpleMessage("Брокер відповів"),
    "errSaidNoAnswer": MessageLookupByLibrary.simpleMessage("Studio чекала"),
    "errSaidStudio": MessageLookupByLibrary.simpleMessage("Що сталося"),
    "errSeeAccess": MessageLookupByLibrary.simpleMessage("Мої права"),
    "errSilentReach": m54,
    "errSilentStatus": m55,
    "errStatusLine": m56,
    "errThingBroker": MessageLookupByLibrary.simpleMessage("брокер"),
    "errThingThis": MessageLookupByLibrary.simpleMessage("це"),
    "errTimeLocal": m57,
    "errTitleBroker": m58,
    "errTitleBrokerNoSite": m59,
    "errTitleBusy": m60,
    "errTitleGone": m61,
    "errTitleHistory": m62,
    "errTitleInput": MessageLookupByLibrary.simpleMessage(
      "Брокер відхилив ці параметри",
    ),
    "errTitleInputValue": MessageLookupByLibrary.simpleMessage(
      "Брокер відхилив це значення",
    ),
    "errTitleNotConnected": MessageLookupByLibrary.simpleMessage(
      "Studio не з’єднана з gateway",
    ),
    "errTitlePlain": MessageLookupByLibrary.simpleMessage(
      "Studio не вдалося це завершити",
    ),
    "errTitleReach": m63,
    "errTitleReachNoSite": MessageLookupByLibrary.simpleMessage(
      "Брокер не відповідає",
    ),
    "errTitleRead": m64,
    "errTitleRights": m65,
    "errTitleStream": m66,
    "errTitleStudio": m67,
    "errTitleUnsupported": m68,
    "errTryAgain": MessageLookupByLibrary.simpleMessage("Спробувати ще раз"),
    "errTryAgainIn": m69,
    "errUserRole": m70,
    "errWhatYouCanDo": MessageLookupByLibrary.simpleMessage("Що можна зробити"),
    "errWriteNote": MessageLookupByLibrary.simpleMessage(
      "Запис, що не дочекався відповіді, міг бути застосований. Перевірте значення, перш ніж надсилати знову.",
    ),
    "eventNone": MessageLookupByLibrary.simpleMessage("ще не було"),
    "everySeconds": m71,
    "factAbout": MessageLookupByLibrary.simpleMessage("Про"),
    "factAgent": MessageLookupByLibrary.simpleMessage("Агент"),
    "factAllowConfig": MessageLookupByLibrary.simpleMessage("Config від нього"),
    "factAskedBy": MessageLookupByLibrary.simpleMessage("Запитав"),
    "factBelow": MessageLookupByLibrary.simpleMessage("Нижче"),
    "factBlocks": MessageLookupByLibrary.simpleMessage("Блоки"),
    "factBranch": MessageLookupByLibrary.simpleMessage("Гілка"),
    "factBuild": MessageLookupByLibrary.simpleMessage("Збірка"),
    "factCanDo": MessageLookupByLibrary.simpleMessage("Може"),
    "factCertificate": MessageLookupByLibrary.simpleMessage("Сертифікат"),
    "factDeployedBy": MessageLookupByLibrary.simpleMessage("Розгорнув"),
    "factDevice": MessageLookupByLibrary.simpleMessage("Пристрій"),
    "factEvents": MessageLookupByLibrary.simpleMessage("Події"),
    "factFlush": MessageLookupByLibrary.simpleMessage("Скидання"),
    "factFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "factGrants": MessageLookupByLibrary.simpleMessage("Дозволи"),
    "factHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "factInterval": MessageLookupByLibrary.simpleMessage("Інтервал"),
    "factKey": MessageLookupByLibrary.simpleMessage("Ключ"),
    "factKind": MessageLookupByLibrary.simpleMessage("Тип"),
    "factLive": MessageLookupByLibrary.simpleMessage("Живі значення"),
    "factLogLevel": MessageLookupByLibrary.simpleMessage("Рівень журналу"),
    "factMayWrite": MessageLookupByLibrary.simpleMessage("Може писати"),
    "factOldest": MessageLookupByLibrary.simpleMessage("Найстаріший день"),
    "factProblem": MessageLookupByLibrary.simpleMessage("Проблема"),
    "factReads": MessageLookupByLibrary.simpleMessage("Читає"),
    "factRecord": MessageLookupByLibrary.simpleMessage("Запис"),
    "factRelays": MessageLookupByLibrary.simpleMessage("Ретранслює"),
    "factRowsWritten": MessageLookupByLibrary.simpleMessage("Записано рядків"),
    "factRunning": MessageLookupByLibrary.simpleMessage("Працює"),
    "factRunsAs": MessageLookupByLibrary.simpleMessage("Працює як"),
    "factSeen": MessageLookupByLibrary.simpleMessage("Побачено"),
    "factSince": MessageLookupByLibrary.simpleMessage("Від"),
    "factStarted": MessageLookupByLibrary.simpleMessage("Запущено"),
    "factStatus": MessageLookupByLibrary.simpleMessage("Стан"),
    "factSubject": MessageLookupByLibrary.simpleMessage("Суб’єкт"),
    "factTask": MessageLookupByLibrary.simpleMessage("Задача"),
    "factTaskState": MessageLookupByLibrary.simpleMessage("Стан"),
    "factThrough": MessageLookupByLibrary.simpleMessage("Через"),
    "factTree": MessageLookupByLibrary.simpleMessage("Дерево"),
    "factUpstreams": MessageLookupByLibrary.simpleMessage("Верхні"),
    "factValues": MessageLookupByLibrary.simpleMessage("Значення"),
    "factVersion": MessageLookupByLibrary.simpleMessage("Версія"),
    "factWrites": MessageLookupByLibrary.simpleMessage("Пише"),
    "failed": MessageLookupByLibrary.simpleMessage("не пройшов"),
    "failedNote": MessageLookupByLibrary.simpleMessage(
      "Задача зупинилась. Те, що вже зроблено, лишається.",
    ),
    "fatalBody": MessageLookupByLibrary.simpleMessage(
      "Налаштування, збережені на цьому комп’ютері, не читаються, тому Studio не знає, які gateway ви використовуєте. Ваші брокери не зачеплено: ніщо на них не залежить від Studio.",
    ),
    "fatalFile": MessageLookupByLibrary.simpleMessage("Файл"),
    "fatalFresh": MessageLookupByLibrary.simpleMessage(
      "Почати з чистими налаштуваннями",
    ),
    "fatalMoveFailed": m72,
    "fatalNote": m73,
    "fatalQuit": MessageLookupByLibrary.simpleMessage("Вийти зі Studio"),
    "fatalTitle": MessageLookupByLibrary.simpleMessage(
      "Studio не вдалося запустити",
    ),
    "faultBody": MessageLookupByLibrary.simpleMessage(
      "Решта Studio працює; значення та дії в інших місцях не зачеплено.",
    ),
    "faultDrawAgain": MessageLookupByLibrary.simpleMessage("Намалювати ще раз"),
    "faultProblem": m74,
    "faultThisPart": MessageLookupByLibrary.simpleMessage("цю частину"),
    "faultTitle": m75,
    "faultTitleThis": MessageLookupByLibrary.simpleMessage(
      "Цю частину не вдалося намалювати",
    ),
    "faultUncaught": MessageLookupByLibrary.simpleMessage(
      "У Studio стався збій у фоні",
    ),
    "fieldAddress": MessageLookupByLibrary.simpleMessage("Адреса"),
    "fieldArea": MessageLookupByLibrary.simpleMessage("Область"),
    "fieldBit": MessageLookupByLibrary.simpleMessage("Біт"),
    "fieldDataType": MessageLookupByLibrary.simpleMessage("Тип даних"),
    "fieldOffset": MessageLookupByLibrary.simpleMessage("Зсув"),
    "fieldPrecision": MessageLookupByLibrary.simpleMessage("Точність"),
    "fieldRegisters": MessageLookupByLibrary.simpleMessage("Регістри"),
    "fieldScale": MessageLookupByLibrary.simpleMessage("Масштаб"),
    "fieldUnit": MessageLookupByLibrary.simpleMessage("Одиниця"),
    "fieldWordOrder": MessageLookupByLibrary.simpleMessage("Порядок слів"),
    "fieldWritable": MessageLookupByLibrary.simpleMessage("Запис дозволено"),
    "fieldWritableByMaster": MessageLookupByLibrary.simpleMessage(
      "Запис від майстра",
    ),
    "filter": MessageLookupByLibrary.simpleMessage("Фільтр"),
    "filterPoints": MessageLookupByLibrary.simpleMessage("Фільтр точок"),
    "findBlock": MessageLookupByLibrary.simpleMessage("Знайти блок"),
    "findInTree": MessageLookupByLibrary.simpleMessage("Знайти точку або дію"),
    "firesAtDeploy": MessageLookupByLibrary.simpleMessage(
      "спрацює при розгортанні",
    ),
    "firesAtDeployNote": MessageLookupByLibrary.simpleMessage(
      "Параметр надсилає значення під час запуску потоку, тож цей зв’язок пише при кожному розгортанні.",
    ),
    "firesAtStartNote": MessageLookupByLibrary.simpleMessage(
      "Це поле надсилає своє значення під час запуску потоку, тож цей зв’язок пише при кожному розгортанні.",
    ),
    "firstSeen": m76,
    "fixFirst": MessageLookupByLibrary.simpleMessage(
      "Чернетка не проходить перевірку.",
    ),
    "flowBack": MessageLookupByLibrary.simpleMessage("Назад"),
    "flowDeployed": m77,
    "flowError": m78,
    "flowName": MessageLookupByLibrary.simpleMessage("Ідентифікатор потоку"),
    "flowPropertiesNote": MessageLookupByLibrary.simpleMessage(
      "Кожне поле має значення, вхід і вихід. Введіть значення або перетягніть на нього будь-який вихід, щоб зв’язати.",
    ),
    "flowPropertiesNote2": MessageLookupByLibrary.simpleMessage(
      "Зв’язане поле показує значення, яке надходить; його зв’язок і джерело світяться, коли на нього навести. Значок зв’язку веде до джерела або розв’язує.",
    ),
    "flowStopped": m79,
    "flowVersion": m80,
    "flowsFooter": MessageLookupByLibrary.simpleMessage(
      "Розгортання потребує config на dataflows; gateway додає ваші докази для кожної цілі. Глядачі можуть лише дивитися.",
    ),
    "flowsOn": m81,
    "flowsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Кожен потік працює в брокері. Ви редагуєте чернетку; нічого не змінюється до розгортання.",
    ),
    "fmBlocks": m82,
    "fmBound": MessageLookupByLibrary.simpleMessage("зв’язане"),
    "fmCanvas": MessageLookupByLibrary.simpleMessage("Полотно"),
    "fmCreateCustom": MessageLookupByLibrary.simpleMessage(
      "Створити власний блок…",
    ),
    "fmEditCustom": MessageLookupByLibrary.simpleMessage(
      "Редагувати власний блок",
    ),
    "fmFields": MessageLookupByLibrary.simpleMessage("Поля"),
    "fmFieldsTitle": MessageLookupByLibrary.simpleMessage("Поля на блоці"),
    "fmNeedsBroker": MessageLookupByLibrary.simpleMessage(
      "Цей брокер не має власних блоків (його рушій флоу старший за ADR 0040)",
    ),
    "fmNeedsEngine": MessageLookupByLibrary.simpleMessage(
      "Потрібні власні блоки в рушії",
    ),
    "fmNotCustom": MessageLookupByLibrary.simpleMessage("Це не власний блок"),
    "fmNothingSelected": MessageLookupByLibrary.simpleMessage(
      "Спершу виділіть блок",
    ),
    "fmNothingToRedo": MessageLookupByLibrary.simpleMessage(
      "Нема чого повторювати",
    ),
    "fmNothingToUndo": MessageLookupByLibrary.simpleMessage(
      "Нема чого скасовувати",
    ),
    "fmUnpin": MessageLookupByLibrary.simpleMessage("Відкріпити від блока"),
    "fmUnpinField": m83,
    "fromAddress": m84,
    "fromTheOfficialList": MessageLookupByLibrary.simpleMessage(
      "З офіційного списку",
    ),
    "gateway": MessageLookupByLibrary.simpleMessage("Gateway"),
    "gatewayAnswered": m85,
    "gatewayNoAnswer": m86,
    "gatewayUrl": MessageLookupByLibrary.simpleMessage("URL gateway"),
    "gatewayUrlHint": MessageLookupByLibrary.simpleMessage(
      "http://host:8445 або кілька через кому",
    ),
    "gatewayUser": MessageLookupByLibrary.simpleMessage("Користувач gateway"),
    "gitRef": MessageLookupByLibrary.simpleMessage("Ref"),
    "gitRepository": MessageLookupByLibrary.simpleMessage(
      "Git-репозиторій (HTTPS)",
    ),
    "goTo": m87,
    "goToSource": MessageLookupByLibrary.simpleMessage("До джерела"),
    "goUp": MessageLookupByLibrary.simpleMessage("Вгору"),
    "grantFor": m88,
    "grantLevel": MessageLookupByLibrary.simpleMessage("Рівень"),
    "grantPath": MessageLookupByLibrary.simpleMessage("Ключ або шаблон"),
    "groupChange": MessageLookupByLibrary.simpleMessage("Змінити"),
    "groupOnTheDevice": MessageLookupByLibrary.simpleMessage(
      "Робиться на пристрої, не тут",
    ),
    "groupRemove": MessageLookupByLibrary.simpleMessage("Видалити"),
    "groupRun": MessageLookupByLibrary.simpleMessage("Робота"),
    "groupVersion": MessageLookupByLibrary.simpleMessage("Версія"),
    "groupWork": MessageLookupByLibrary.simpleMessage("Робота з ним"),
    "groupYouControl": MessageLookupByLibrary.simpleMessage(
      "Що ви контролюєте тут",
    ),
    "grpArguments": MessageLookupByLibrary.simpleMessage("Аргументи"),
    "grpBehaviour": MessageLookupByLibrary.simpleMessage("Поведінка"),
    "grpEvents": MessageLookupByLibrary.simpleMessage("Події"),
    "grpState": MessageLookupByLibrary.simpleMessage("Стан"),
    "grpTarget": MessageLookupByLibrary.simpleMessage("Ціль"),
    "heroHeadline1": MessageLookupByLibrary.simpleMessage(
      "Кожен пристрій, лінк і сайт",
    ),
    "heroHeadline2": MessageLookupByLibrary.simpleMessage(
      "в одному живому дереві.",
    ),
    "heroLead": MessageLookupByLibrary.simpleMessage(
      "Переглядайте, що тримають ваші брокери, додавайте лінки, впускайте пристрої, з’єднуйте сайти та будуйте потоки. Нічого не зміниться, доки ви не застосуєте зміни.",
    ),
    "hidePassword": MessageLookupByLibrary.simpleMessage("Сховати пароль"),
    "historianKeep": m89,
    "historianSeries": m90,
    "historianSize": m91,
    "historyFooter": MessageLookupByLibrary.simpleMessage(
      "Лінки синхронізації читають журнал змін історика, тож нічого не губиться, поки база недоступна.",
    ),
    "historyOf": m92,
    "historyUnavailable": MessageLookupByLibrary.simpleMessage(
      "історія недоступна",
    ),
    "historyUnavailableTip": m93,
    "holdUnknown": MessageLookupByLibrary.simpleMessage(
      "Тримати невідомі з’єднання тут",
    ),
    "holdUnknownNote": MessageLookupByLibrary.simpleMessage(
      "Вимкнено (і «Допускати всі» вимкнено): невідомі сертифікати ігноруються.",
    ),
    "howItRunsThere": MessageLookupByLibrary.simpleMessage("Як він там працює"),
    "importPoints": MessageLookupByLibrary.simpleMessage(
      "Імпорт CSV або дерева DSA",
    ),
    "inputsCount": m94,
    "insAction": MessageLookupByLibrary.simpleMessage("Дія"),
    "insBroker": MessageLookupByLibrary.simpleMessage("Брокер"),
    "insConnection": MessageLookupByLibrary.simpleMessage("Зʼєднання"),
    "insDevice": MessageLookupByLibrary.simpleMessage("Пристрій"),
    "insFolder": MessageLookupByLibrary.simpleMessage("Тека"),
    "insLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "insNode": MessageLookupByLibrary.simpleMessage("Вузол"),
    "insPoint": MessageLookupByLibrary.simpleMessage("Точка"),
    "insStorage": MessageLookupByLibrary.simpleMessage("Сховище"),
    "install": MessageLookupByLibrary.simpleMessage("Встановити"),
    "installRailNote": MessageLookupByLibrary.simpleMessage(
      "Встановлення потребує config на sys (роль admin). Нічого не встановлюється, доки ви не натиснете «Встановити».",
    ),
    "installedOn": m95,
    "instancesInFlow": m96,
    "invalidGatewayUrl": MessageLookupByLibrary.simpleMessage(
      "Це не URL gateway (http:// або https:// і хост)",
    ),
    "issue": MessageLookupByLibrary.simpleMessage("Видати"),
    "keyCopied": MessageLookupByLibrary.simpleMessage("Ключ скопійовано"),
    "keysCopied": m97,
    "kindAction": MessageLookupByLibrary.simpleMessage("Дія"),
    "kindBlockPorts": MessageLookupByLibrary.simpleMessage("Власний блок"),
    "kindBroker": MessageLookupByLibrary.simpleMessage("брокер"),
    "kindConnection": MessageLookupByLibrary.simpleMessage("зʼєднання"),
    "kindDataflow": MessageLookupByLibrary.simpleMessage("потік даних"),
    "kindDevice": MessageLookupByLibrary.simpleMessage("пристрій"),
    "kindFlow": MessageLookupByLibrary.simpleMessage("Потік"),
    "kindFolder": MessageLookupByLibrary.simpleMessage("тека"),
    "kindLink": MessageLookupByLibrary.simpleMessage("лінк"),
    "kindLogic": MessageLookupByLibrary.simpleMessage("Логічний блок"),
    "kindMyBlock": MessageLookupByLibrary.simpleMessage("Власний блок"),
    "kindNode": MessageLookupByLibrary.simpleMessage("вузол"),
    "kindSink": MessageLookupByLibrary.simpleMessage("Вихід"),
    "kindStorage": MessageLookupByLibrary.simpleMessage("сховище"),
    "kindTreeNode": MessageLookupByLibrary.simpleMessage("Вузол дерева"),
    "lag": m98,
    "languageName": MessageLookupByLibrary.simpleMessage("Українська"),
    "lastRead": m99,
    "legendCommands": MessageLookupByLibrary.simpleMessage("команди"),
    "legendConnected": MessageLookupByLibrary.simpleMessage("під’єднано"),
    "legendFree": MessageLookupByLibrary.simpleMessage("вільне поле"),
    "legendNote": MessageLookupByLibrary.simpleMessage(
      "Анімація — лише прикраса; вона зупиняється, коли система просить менше руху.",
    ),
    "legendOffline": MessageLookupByLibrary.simpleMessage("офлайн"),
    "legendPlatform": MessageLookupByLibrary.simpleMessage("платформа"),
    "legendReadOnly": MessageLookupByLibrary.simpleMessage(
      "без лівого порту = точка лише для читання",
    ),
    "legendReads": MessageLookupByLibrary.simpleMessage("читає значення"),
    "legendValues": MessageLookupByLibrary.simpleMessage("потік значень"),
    "legendWaiting": MessageLookupByLibrary.simpleMessage("чекає в карантині"),
    "legendWrites": MessageLookupByLibrary.simpleMessage("пише в пристрій"),
    "letItIn": MessageLookupByLibrary.simpleMessage("Допустити"),
    "letOthersIn": MessageLookupByLibrary.simpleMessage("Допустити інших"),
    "letTheBrokerIn": MessageLookupByLibrary.simpleMessage("Допустити брокер"),
    "lightTheme": MessageLookupByLibrary.simpleMessage("Світла тема"),
    "linkName": MessageLookupByLibrary.simpleMessage("Назва лінка"),
    "linkOverTls": MessageLookupByLibrary.simpleMessage("лінк · через tls"),
    "linksAlready": m100,
    "linksCount": m101,
    "linksLocalNote": m102,
    "linksOn": m103,
    "linksQuarantineNote": MessageLookupByLibrary.simpleMessage(
      "З’єднання із сертифікатом цього сайту, для яких немає лінка. Вони нічого не читають і не пишуть, доки ви їх не схвалите.",
    ),
    "linksRemoteNote": MessageLookupByLibrary.simpleMessage(
      "Вони працюють на своїх машинах і під’єднуються із сертифікатом цього сайту. Ви вирішуєте, що їм доступно і чи лишаються вони; сам пристрій оновлюють там, де він працює.",
    ),
    "linksSubtitle": MessageLookupByLibrary.simpleMessage(
      "Лінками на цьому брокері ви керуєте повністю. Лінки на інших пристроях ви лише допускаєте, обмежуєте або відключаєте.",
    ),
    "listAnd": m104,
    "liveRefused": MessageLookupByLibrary.simpleMessage(
      "Ви не можете читати всі джерела й цілі цього потоку",
    ),
    "loading": MessageLookupByLibrary.simpleMessage("Завантаження…"),
    "logEmpty": MessageLookupByLibrary.simpleMessage("Рядків немає."),
    "logIn": MessageLookupByLibrary.simpleMessage("Увійти"),
    "logInLead": MessageLookupByLibrary.simpleMessage(
      "до gateway брокера. Ваша роль там визначає, що ви можете змінювати.",
    ),
    "logInSubtitle": MessageLookupByLibrary.simpleMessage(
      "Увійдіть у gateway WYRM.",
    ),
    "logOf": m105,
    "logOut": MessageLookupByLibrary.simpleMessage("Вийти"),
    "mAclDenials": MessageLookupByLibrary.simpleMessage("Відмови ACL"),
    "mAuditRecords": MessageLookupByLibrary.simpleMessage("Записи аудиту"),
    "mFreeDisk": MessageLookupByLibrary.simpleMessage("Вільний диск"),
    "mInQuarantine": MessageLookupByLibrary.simpleMessage("У карантині"),
    "mLinksConnected": MessageLookupByLibrary.simpleMessage(
      "Лінків під’єднано",
    ),
    "mMemory": MessageLookupByLibrary.simpleMessage("Пам’ять"),
    "mSessions": MessageLookupByLibrary.simpleMessage("Сесії"),
    "mStandby": MessageLookupByLibrary.simpleMessage("Резерв"),
    "mUpDown": MessageLookupByLibrary.simpleMessage("Верхні / нижні"),
    "manifest": MessageLookupByLibrary.simpleMessage("Маніфест"),
    "mayDoNote": MessageLookupByLibrary.simpleMessage(
      "Це параметри самого link агента. Зміни їх у Links › Edit params.",
    ),
    "mbBackFirst": MessageLookupByLibrary.simpleMessage(
      "Спершу повернися до флоу",
    ),
    "mbDelete": MessageLookupByLibrary.simpleMessage("Видалити"),
    "mbEdit": MessageLookupByLibrary.simpleMessage("Редагувати власний блок"),
    "mbInUse": m106,
    "mbInsideItself": MessageLookupByLibrary.simpleMessage(
      "Блок не може містити сам себе",
    ),
    "mbNotInLibrary": MessageLookupByLibrary.simpleMessage(
      "У бібліотеці немає блока з такою назвою",
    ),
    "mbRemoveLibrary": MessageLookupByLibrary.simpleMessage(
      "Видалити з бібліотеки",
    ),
    "mbRename": MessageLookupByLibrary.simpleMessage("Перейменувати"),
    "mbSameVersion": MessageLookupByLibrary.simpleMessage(
      "Флоу має версію з бібліотеки",
    ),
    "mbSave": MessageLookupByLibrary.simpleMessage("Зберегти в бібліотеку"),
    "mbUpdate": MessageLookupByLibrary.simpleMessage("Оновити з бібліотеки"),
    "mbUpdateTo": m107,
    "mbUsed": m108,
    "mbVersion": m109,
    "menuLanguage": MessageLookupByLibrary.simpleMessage("Мова"),
    "menuOther": MessageLookupByLibrary.simpleMessage("Інше"),
    "menuSubtitle": m110,
    "menuTheme": MessageLookupByLibrary.simpleMessage("Тема"),
    "messagesPerSecond": MessageLookupByLibrary.simpleMessage(
      "Повідомлень роутера за секунду",
    ),
    "modeEmbedded": MessageLookupByLibrary.simpleMessage("Вбудований"),
    "modeEmbeddedNote": MessageLookupByLibrary.simpleMessage(
      "Усередині брокера: найлегший; зупиняється разом із брокером.",
    ),
    "modeExternal": MessageLookupByLibrary.simpleMessage("Зовнішній"),
    "modeExternalNote": MessageLookupByLibrary.simpleMessage(
      "На іншій машині: під’єднується із сертифікатом цього сайту.",
    ),
    "modeProcess": MessageLookupByLibrary.simpleMessage("Процес"),
    "modeProcessNote": MessageLookupByLibrary.simpleMessage(
      "Окремий процес на цьому хості; брокер стежить і перезапускає.",
    ),
    "modeWasmNote": MessageLookupByLibrary.simpleMessage(
      "Усередині брокера в пісочниці: без файлів, лише дозволена мережа, обмеження пам’яті й часу. Визначається типом пакета.",
    ),
    "more": MessageLookupByLibrary.simpleMessage("Ще"),
    "moreBytes": m111,
    "myBlocksEmpty": MessageLookupByLibrary.simpleMessage(
      "Власних блоків ще немає. Вибери блоки на полотні та натисни «Створити власний блок…» у їхньому меню.",
    ),
    "myBlocksLibrary": MessageLookupByLibrary.simpleMessage("Бібліотека сайту"),
    "myBlocksOff": MessageLookupByLibrary.simpleMessage(
      "Цей брокер не має власних блоків: його рушій флоу старший за ADR 0040.",
    ),
    "myBlocksReason": MessageLookupByLibrary.simpleMessage(
      "Потрібні власні блоки в рушії",
    ),
    "myBlocksThisFlow": MessageLookupByLibrary.simpleMessage("Цей флоу"),
    "nSelected": m112,
    "nameIt": MessageLookupByLibrary.simpleMessage("Дайте лінку назву."),
    "nameRule": MessageLookupByLibrary.simpleMessage(
      "Літери, цифри, . _ - · не зайнята іншим лінком, видаленим лінком або сайтом",
    ),
    "nameTaken": MessageLookupByLibrary.simpleMessage(
      "Ця назва вже є в іншого лінка.",
    ),
    "needsConfigOnSys": MessageLookupByLibrary.simpleMessage(
      "Потрібен config на sys",
    ),
    "needsLevelYouHave": m113,
    "needsLevelYouHaveIt": m114,
    "networkError": MessageLookupByLibrary.simpleMessage(
      "Проблема зі з’єднанням",
    ),
    "newCertificate": MessageLookupByLibrary.simpleMessage("новий сертифікат"),
    "newDataflow": MessageLookupByLibrary.simpleMessage("Новий потік"),
    "newTask": MessageLookupByLibrary.simpleMessage("Нова задача"),
    "newValue": MessageLookupByLibrary.simpleMessage("Нове значення"),
    "no": MessageLookupByLibrary.simpleMessage("ні"),
    "noActionReason": m115,
    "noAgent": MessageLookupByLibrary.simpleMessage(
      "На цьому сайті немає асистента. Асистент — це link агента: додай його, дай йому API-ключ і питай тут.",
    ),
    "noAudit": MessageLookupByLibrary.simpleMessage(
      "Немає записів аудиту, доступних вам.",
    ),
    "noAuditHere": MessageLookupByLibrary.simpleMessage(
      "Немає записів для цього вузла серед останніх 500 у sys/audit.",
    ),
    "noChildren": MessageLookupByLibrary.simpleMessage(
      "Під цим вузлом нічого немає.",
    ),
    "noEditReason": MessageLookupByLibrary.simpleMessage(
      "Ця точка не має дії edit.",
    ),
    "noFlows": MessageLookupByLibrary.simpleMessage(
      "На цьому сайті ще немає потоків.",
    ),
    "noGrants": MessageLookupByLibrary.simpleMessage(
      "Немає дозволів, доступних вам.",
    ),
    "noHistory": MessageLookupByLibrary.simpleMessage(
      "Немає записаних значень у цьому проміжку. Точку записує спостереження в sys/history.",
    ),
    "noHistoryAction": MessageLookupByLibrary.simpleMessage(
      "Запис точки налаштовується в Історії (групи спостереження).",
    ),
    "noLocalLinks": MessageLookupByLibrary.simpleMessage(
      "На цьому брокері ще немає лінків. Додайте лінк, щоб під’єднати пристрій.",
    ),
    "noParamReason": m116,
    "noPingReason": MessageLookupByLibrary.simpleMessage(
      "Цей вузол не має дії ping: драйвер пінгує сам (cfg ping).",
    ),
    "noPoints": MessageLookupByLibrary.simpleMessage(
      "Тут немає значень. Відкрийте гілку в дереві.",
    ),
    "noPointsYet": MessageLookupByLibrary.simpleMessage("Ще немає точок"),
    "noProfileReason": MessageLookupByLibrary.simpleMessage(
      "Брокер ще не має дії, що застосовує профіль до пристрою.",
    ),
    "noReadFlow": MessageLookupByLibrary.simpleMessage(
      "Щоб відкрити редактор, потрібне право read на цей потік.",
    ),
    "noRemoteLinks": MessageLookupByLibrary.simpleMessage(
      "Жоден пристрій не під’єднаний як зовнішній лінк.",
    ),
    "noRevisions": MessageLookupByLibrary.simpleMessage("Ревізій немає."),
    "noTasks": MessageLookupByLibrary.simpleMessage(
      "Опиши зміну. Агент читає дерево, пише план і чекає схвалення. Нічого не зміниться без твого схвалення.",
    ),
    "noUpstream": m117,
    "noUsers": MessageLookupByLibrary.simpleMessage(
      "Немає користувачів, доступних вам.",
    ),
    "noValue": MessageLookupByLibrary.simpleMessage("немає значення"),
    "noWatchGroups": MessageLookupByLibrary.simpleMessage(
      "Груп спостереження ще немає. Додайте, щоб записувати точки.",
    ),
    "noWatchPaths": MessageLookupByLibrary.simpleMessage(
      "У цій групі немає точок.",
    ),
    "none": MessageLookupByLibrary.simpleMessage("немає"),
    "noneAsked": MessageLookupByLibrary.simpleMessage("не запитано"),
    "notApplied": MessageLookupByLibrary.simpleMessage("не застосовано"),
    "notBound": MessageLookupByLibrary.simpleMessage("не зв’язано"),
    "notDeployed": MessageLookupByLibrary.simpleMessage("не розгорнуто"),
    "notInstalled": MessageLookupByLibrary.simpleMessage(
      "Брокер не встановив його.",
    ),
    "notRecorded": MessageLookupByLibrary.simpleMessage("не записується"),
    "notWritable": MessageLookupByLibrary.simpleMessage(
      "Лише читання: драйвер не приймає тут значення.",
    ),
    "noteAction": MessageLookupByLibrary.simpleMessage(
      "Перетягнута з дерева. Запускається, коли run when стає true.",
    ),
    "noteActionBlock": MessageLookupByLibrary.simpleMessage(
      "Дія з дерева. Запускається за тригером, за зміною аргументу, за періодом або кнопкою «Запустити».",
    ),
    "noteBlockInputs": MessageLookupByLibrary.simpleMessage(
      "Що блок приймає. Перетягни дріт від входу до кожного внутрішнього поля, яке він живить; тут введи його значення за замовчуванням. + додає вхід.",
    ),
    "noteBlockOutputs": MessageLookupByLibrary.simpleMessage(
      "Що блок віддає. Перетягни внутрішній вихід на кожен. + додає вихід.",
    ),
    "noteTreeNode": MessageLookupByLibrary.simpleMessage(
      "Точка дерева. Точка лише для читання не має входу; зв’язок у записувану точку пише ~set.",
    ),
    "nothingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "У карантині нічого не чекає.",
    ),
    "nothingStaged": MessageLookupByLibrary.simpleMessage(
      "Нічого не підготовлено. Змініть значення або параметр.",
    ),
    "nothingToDeploy": MessageLookupByLibrary.simpleMessage(
      "Нічого розгортати",
    ),
    "now": MessageLookupByLibrary.simpleMessage("зараз"),
    "officialList": MessageLookupByLibrary.simpleMessage("Офіційний список"),
    "officialListNote": MessageLookupByLibrary.simpleMessage(
      "Драйвери у wyrmd і пакети з вашого репозиторію. Оберіть, де працюватиме, і встановіть.",
    ),
    "offline": MessageLookupByLibrary.simpleMessage(
      "З’єднання з gateway втрачено. Перепідключення; на екрані останні отримані значення.",
    ),
    "ok": MessageLookupByLibrary.simpleMessage("OK"),
    "onOtherDevices": MessageLookupByLibrary.simpleMessage(
      "На інших пристроях",
    ),
    "onThisBroker": MessageLookupByLibrary.simpleMessage("На цьому брокері"),
    "onWhichBroker": MessageLookupByLibrary.simpleMessage("На якому брокері"),
    "openInExplorer": MessageLookupByLibrary.simpleMessage("Відкрити в дереві"),
    "openInLinks": MessageLookupByLibrary.simpleMessage("Відкрити в Лінках"),
    "openInLinksNote": MessageLookupByLibrary.simpleMessage(
      "Доступи, відкликання і видалення — у Лінках › На інших пристроях.",
    ),
    "openInside": MessageLookupByLibrary.simpleMessage("Відкрити вміст"),
    "openItsTree": MessageLookupByLibrary.simpleMessage("Відкрити його дерево"),
    "openItsTreeNote": m118,
    "openingTree": MessageLookupByLibrary.simpleMessage("Відкриваємо дерево"),
    "openingTreeOf": m119,
    "operateRunsNow": MessageLookupByLibrary.simpleMessage(
      "Керування · виконується одразу",
    ),
    "operateRunsNowNote": MessageLookupByLibrary.simpleMessage(
      "Виконується на пристрої з вашими правами і записується в аудит.",
    ),
    "package": MessageLookupByLibrary.simpleMessage("пакет"),
    "packageNamed": m120,
    "packageSummary": MessageLookupByLibrary.simpleMessage(
      "Пакет із вашого репозиторію · SHA-256 звіряється з індексом під час завантаження",
    ),
    "packageUrl": MessageLookupByLibrary.simpleMessage("URL пакета (HTTPS)"),
    "pairsCount": m121,
    "paletteBlocks": MessageLookupByLibrary.simpleMessage("Блоки"),
    "paletteMyBlocks": MessageLookupByLibrary.simpleMessage("Мої блоки"),
    "paletteTree": MessageLookupByLibrary.simpleMessage("Дерево"),
    "panelCanvas": MessageLookupByLibrary.simpleMessage("полотно редактора"),
    "panelDrawer": MessageLookupByLibrary.simpleMessage("бічна панель"),
    "panelInspector": MessageLookupByLibrary.simpleMessage("інспектор"),
    "panelMayDo": MessageLookupByLibrary.simpleMessage("Що йому можна"),
    "panelThisTask": MessageLookupByLibrary.simpleMessage("Ця задача"),
    "panelTree": MessageLookupByLibrary.simpleMessage("дерево"),
    "panelWorkspace": MessageLookupByLibrary.simpleMessage("робоча область"),
    "paramCount": m122,
    "paramsJson": m123,
    "paramsNotJson": m124,
    "paramsNotObject": MessageLookupByLibrary.simpleMessage(
      "Параметри мають бути одним об’єктом JSON.",
    ),
    "paramsNote": MessageLookupByLibrary.simpleMessage(
      "~meta вузла, як його оголошує брокер: профіль, cfg і attr.",
    ),
    "passed": MessageLookupByLibrary.simpleMessage("пройшов"),
    "password": MessageLookupByLibrary.simpleMessage("Пароль"),
    "pickAPoint": MessageLookupByLibrary.simpleMessage(
      "Виберіть точку в таблиці, щоб побачити її історію.",
    ),
    "pickOne": MessageLookupByLibrary.simpleMessage("Оберіть лінк зі списку."),
    "pinField": MessageLookupByLibrary.simpleMessage("Закріпити на блоці"),
    "pinLocked": MessageLookupByLibrary.simpleMessage(
      "Зв’язане поле лишається на блоці",
    ),
    "ping": MessageLookupByLibrary.simpleMessage("Пінг"),
    "planCard": MessageLookupByLibrary.simpleMessage("План"),
    "planNote": MessageLookupByLibrary.simpleMessage(
      "План записаний у задачі. Studio покаже його, коли gateway зможе читати документи (docs/studio.md §10 п. 11). Поки що читай план через wyrm-agent.",
    ),
    "platform": MessageLookupByLibrary.simpleMessage("Платформа"),
    "platformNote": MessageLookupByLibrary.simpleMessage(
      "Його налаштування і лічильники — у downstream/uplink.",
    ),
    "pleaseCheckYourNetworkSettings": MessageLookupByLibrary.simpleMessage(
      "Перевірте налаштування мережі.",
    ),
    "pleaseLogInAgain": MessageLookupByLibrary.simpleMessage(
      "Увійдіть ще раз.",
    ),
    "pointsCount": m125,
    "pointsNote": MessageLookupByLibrary.simpleMessage(
      "Значення оновлюються наживо. Зміни готуються в цій сесії; нічого не записується в пристрій до застосування.",
    ),
    "portsCount": m126,
    "preloadBlocks": MessageLookupByLibrary.simpleMessage(
      "Читання блоків потоків",
    ),
    "preloadFlows": MessageLookupByLibrary.simpleMessage("Читання потоків"),
    "preloadLater": m127,
    "preloadLinks": MessageLookupByLibrary.simpleMessage("Читання лінків"),
    "preloadSites": MessageLookupByLibrary.simpleMessage("Читання сайтів"),
    "preloadTree": m128,
    "previewInvalid": m129,
    "previewTag": MessageLookupByLibrary.simpleMessage("перегляд"),
    "problems": MessageLookupByLibrary.simpleMessage("Проблеми"),
    "problemsClear": MessageLookupByLibrary.simpleMessage("Очистити все"),
    "problemsClose": MessageLookupByLibrary.simpleMessage("Закрити проблеми"),
    "problemsCount": m130,
    "problemsEmpty": MessageLookupByLibrary.simpleMessage(
      "У цьому сеансі проблем немає.",
    ),
    "problemsNote": MessageLookupByLibrary.simpleMessage(
      "Збої того, що Studio робила сама (читання, оновлення, живі значення), і кожен закритий діалог. Зберігаються до закриття Studio; найновіші зверху.",
    ),
    "problemsShown": MessageLookupByLibrary.simpleMessage("показано як діалог"),
    "problemsTitle": MessageLookupByLibrary.simpleMessage(
      "Проблеми · цей сеанс",
    ),
    "purgeHistory": MessageLookupByLibrary.simpleMessage(
      "Видалити проміжок часу",
    ),
    "purgeHistoryNote": MessageLookupByLibrary.simpleMessage(
      "Видаляє записані рядки проміжку для всіх точок.",
    ),
    "qCheckFailed": MessageLookupByLibrary.simpleMessage(
      "Пакет не пройшов перевірку",
    ),
    "qCheckOk": MessageLookupByLibrary.simpleMessage(
      "Пакет виглядає правильно",
    ),
    "qChoose": MessageLookupByLibrary.simpleMessage("Що ви хочете додати?"),
    "qFailed": MessageLookupByLibrary.simpleMessage("Брокер не встановив його"),
    "qInstalled": m131,
    "qInstalling": m132,
    "qRun": MessageLookupByLibrary.simpleMessage(
      "Де він працюватиме і під якою назвою?",
    ),
    "quarantine": MessageLookupByLibrary.simpleMessage("Карантин"),
    "quarantineAndAdmission": MessageLookupByLibrary.simpleMessage(
      "Карантин і допуск",
    ),
    "quarantineAndAdmissionNote": MessageLookupByLibrary.simpleMessage(
      "Невідомі сертифікати чекають у Лінках › Карантин.",
    ),
    "reachesSites": m133,
    "readFailed": MessageLookupByLibrary.simpleMessage("не прочитано"),
    "readFailedTip": m134,
    "readsNote": MessageLookupByLibrary.simpleMessage(
      "Читання не потребує схвалення. Агент читає лише в межах ваших прав і своїх.",
    ),
    "recordInHistory": MessageLookupByLibrary.simpleMessage(
      "Записувати в історію…",
    ),
    "recorded": MessageLookupByLibrary.simpleMessage("записується"),
    "refresh": MessageLookupByLibrary.simpleMessage("Оновити"),
    "refuseLoop": MessageLookupByLibrary.simpleMessage(
      "Це замикає цикл (лише через delay)",
    ),
    "refuseNeedsBroker": m135,
    "refuseNoInput": m136,
    "refuseOutput": MessageLookupByLibrary.simpleMessage(
      "Вихід не можна зв’язати",
    ),
    "refuseSelf": MessageLookupByLibrary.simpleMessage(
      "Блок не може живити сам себе",
    ),
    "refuseType": m137,
    "reject": MessageLookupByLibrary.simpleMessage("Відхилити"),
    "rejectNote": MessageLookupByLibrary.simpleMessage(
      "Цей сертифікат надалі відхилятиметься.",
    ),
    "rejectTitle": m138,
    "relayedFooter": MessageLookupByLibrary.simpleMessage(
      "Звідси нічого робити: він прийшов разом зі своїм ретранслятором. Відкличте ретранслятор, щоб відрізати його.",
    ),
    "relaysSites": m139,
    "rememberGatewayAndUser": MessageLookupByLibrary.simpleMessage(
      "Запам’ятати gateway і користувача на цьому комп’ютері",
    ),
    "remoteFooter": MessageLookupByLibrary.simpleMessage(
      "Якщо пристрій втрачено або вкрадено: «Видалити назавжди». Відкликання — це пауза: схваліть знову з карантину, і він збереже ім’я та дерево.",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("Видалити"),
    "removeBlock": MessageLookupByLibrary.simpleMessage("Видалити блок"),
    "removeDeletesTree": MessageLookupByLibrary.simpleMessage(
      "Його буде зупинено, дерево видалено. Ім’я можна використати знову.",
    ),
    "removeEllipsis": MessageLookupByLibrary.simpleMessage("Видалити…"),
    "removeGroup": MessageLookupByLibrary.simpleMessage("Видалити групу"),
    "removeGroupNote": MessageLookupByLibrary.simpleMessage(
      "Запис зупиниться; рядки лишаються, якщо не видалити їх.",
    ),
    "removeInput": MessageLookupByLibrary.simpleMessage(
      "Прибрати останній вхід",
    ),
    "removeLinkTitle": m140,
    "removePair": MessageLookupByLibrary.simpleMessage(
      "Прибрати останній випадок",
    ),
    "removePort": MessageLookupByLibrary.simpleMessage(
      "Прибрати останній порт",
    ),
    "removeRetiresId": MessageLookupByLibrary.simpleMessage(
      "Його буде зупинено, дерево видалено, а id вилучено: його не можна використати знову.",
    ),
    "removeUser": MessageLookupByLibrary.simpleMessage("Видалити користувача"),
    "removeUserNote": MessageLookupByLibrary.simpleMessage(
      "Він більше не зможе увійти; його сесії завершаться.",
    ),
    "removeUserTitle": m141,
    "requiredField": MessageLookupByLibrary.simpleMessage("Обов’язкове поле"),
    "resultOf": m142,
    "returns": m143,
    "review": MessageLookupByLibrary.simpleMessage("Перегляд"),
    "reviewAndApply": MessageLookupByLibrary.simpleMessage(
      "Переглянути й застосувати",
    ),
    "reviewNote": m144,
    "revision": m145,
    "revisionNow": m146,
    "rightsLine": m147,
    "rightsNote": MessageLookupByLibrary.simpleMessage(
      "Без цього брокер нічого не встановить. Доступи змінюються пізніше через «Надати доступ», інше — параметрами лінка.",
    ),
    "rightsTitle": MessageLookupByLibrary.simpleMessage(
      "Пакет просить такі права",
    ),
    "roleOnSite": m148,
    "rollBack": MessageLookupByLibrary.simpleMessage("Повернути"),
    "rollBackNote": MessageLookupByLibrary.simpleMessage(
      "Ці параметри стануть новою ревізією, і лінк перезапуститься з ними.",
    ),
    "rollBackTo": m149,
    "rowsAnswered": m150,
    "runBlock": MessageLookupByLibrary.simpleMessage("Запустити"),
    "runDraft": MessageLookupByLibrary.simpleMessage(
      "Спершу розгорни: «Запустити» діє на розгорнуту версію, а чернетка від неї відрізняється",
    ),
    "runNoBroker": MessageLookupByLibrary.simpleMessage(
      "Цей брокер не має дії trigger (його рушій флоу старший за ADR 0040)",
    ),
    "runNoInstance": MessageLookupByLibrary.simpleMessage(
      "Відкрий блок з екземпляра, щоб запустити його",
    ),
    "runNotDeployed": MessageLookupByLibrary.simpleMessage(
      "Спершу розгорни флоу",
    ),
    "runNow": MessageLookupByLibrary.simpleMessage("Виконати"),
    "runNowNote": m151,
    "runOff": MessageLookupByLibrary.simpleMessage("Блок вимкнено"),
    "runOnStartTitle": MessageLookupByLibrary.simpleMessage(
      "Запускати на кожному старті?",
    ),
    "running": MessageLookupByLibrary.simpleMessage("Працює"),
    "runningNote": MessageLookupByLibrary.simpleMessage(
      "Агент працює над задачею. Скасування зупиняє її; зроблене лишається.",
    ),
    "runsOn": m152,
    "runsOnAnotherDevice": MessageLookupByLibrary.simpleMessage(
      "Працює на іншому пристрої",
    ),
    "sameCallCli": MessageLookupByLibrary.simpleMessage(
      "Той самий виклик з CLI",
    ),
    "scAddToSelection": MessageLookupByLibrary.simpleMessage(
      "Додати до виділення або зняти",
    ),
    "scClick": MessageLookupByLibrary.simpleMessage("клік"),
    "scCopy": MessageLookupByLibrary.simpleMessage("Копіювати"),
    "scCut": MessageLookupByLibrary.simpleMessage("Вирізати"),
    "scDelete": MessageLookupByLibrary.simpleMessage("Видалити"),
    "scDeploy": MessageLookupByLibrary.simpleMessage(
      "Розгорнути (з підтвердженням)",
    ),
    "scDoubleClick": MessageLookupByLibrary.simpleMessage("подвійний клік"),
    "scDrag": MessageLookupByLibrary.simpleMessage("тягнути"),
    "scDragEmpty": MessageLookupByLibrary.simpleMessage(
      "тягнути по порожньому полотну",
    ),
    "scDragHeader": MessageLookupByLibrary.simpleMessage("тягнути заголовок"),
    "scDuplicate": MessageLookupByLibrary.simpleMessage("Дублювати"),
    "scEscape": MessageLookupByLibrary.simpleMessage(
      "Скасувати, зняти виділення",
    ),
    "scGroupEdit": MessageLookupByLibrary.simpleMessage("Редагування"),
    "scGroupSelect": MessageLookupByLibrary.simpleMessage("Виділення"),
    "scGroupView": MessageLookupByLibrary.simpleMessage("Вигляд і потік"),
    "scHelp": MessageLookupByLibrary.simpleMessage("Ця картка"),
    "scMarquee": MessageLookupByLibrary.simpleMessage("Виділити рамкою"),
    "scMiddleDrag": MessageLookupByLibrary.simpleMessage(
      "тягнути середньою кнопкою",
    ),
    "scMoveSelection": MessageLookupByLibrary.simpleMessage(
      "Перемістити виділене",
    ),
    "scNote": MessageLookupByLibrary.simpleMessage(
      "Клавіші діють, доки фокус не в текстовому полі.",
    ),
    "scNudge": MessageLookupByLibrary.simpleMessage("Зсунути на крок сітки"),
    "scNudgeFar": MessageLookupByLibrary.simpleMessage("10 кроків"),
    "scOr": MessageLookupByLibrary.simpleMessage("або"),
    "scPan": MessageLookupByLibrary.simpleMessage("Прокрутити полотно"),
    "scPaste": MessageLookupByLibrary.simpleMessage("Вставити"),
    "scPinch": MessageLookupByLibrary.simpleMessage("щипок"),
    "scRedo": MessageLookupByLibrary.simpleMessage("Повторити дію"),
    "scScroll": MessageLookupByLibrary.simpleMessage("колесо / два пальці"),
    "scSearchPalette": MessageLookupByLibrary.simpleMessage("Знайти блок"),
    "scSelectAll": MessageLookupByLibrary.simpleMessage("Виділити все"),
    "scSpace": MessageLookupByLibrary.simpleMessage("Пробіл"),
    "scTitle": MessageLookupByLibrary.simpleMessage("Клавіатура і миша"),
    "scUnbind": MessageLookupByLibrary.simpleMessage("Розв’язати поле"),
    "scUndo": MessageLookupByLibrary.simpleMessage("Скасувати дію"),
    "scViewValue": MessageLookupByLibrary.simpleMessage(
      "Переглянути значення під вказівником",
    ),
    "scWheel": MessageLookupByLibrary.simpleMessage("колесо"),
    "scZoom": MessageLookupByLibrary.simpleMessage("Масштаб"),
    "scZoomFit": MessageLookupByLibrary.simpleMessage("Показати всі блоки"),
    "scZoomIn": MessageLookupByLibrary.simpleMessage("Збільшити"),
    "scZoomOut": MessageLookupByLibrary.simpleMessage("Зменшити"),
    "scZoomReset": MessageLookupByLibrary.simpleMessage("Масштаб 100 %"),
    "scopeEdit": MessageLookupByLibrary.simpleMessage("Змінити межі"),
    "scopeEmpty": MessageLookupByLibrary.simpleMessage(
      "Введи межі: ключ із дроту їх потребує",
    ),
    "scopeNote": MessageLookupByLibrary.simpleMessage(
      "Ключ, що приходить дротом, читається лише в цих межах. Той, хто розгортає, має читати їх усі.",
    ),
    "scopeOtherSite": MessageLookupByLibrary.simpleMessage(
      "Межі лежать у цьому сайті",
    ),
    "scopeSection": MessageLookupByLibrary.simpleMessage(
      "Межі починаються з downstream, dataflows або storage",
    ),
    "scopeSegment": MessageLookupByLibrary.simpleMessage(
      "Це не вираз ключа: сегменти з літер, цифр, _ . - або * та **",
    ),
    "scopeTitle": MessageLookupByLibrary.simpleMessage(
      "Цей блок може читати ключі в межах",
    ),
    "screenOf": m153,
    "searchHint": MessageLookupByLibrary.simpleMessage(
      "Перейти до вузла, дії або лінка",
    ),
    "searchLinks": MessageLookupByLibrary.simpleMessage("Шукати у списку"),
    "secAttributes": MessageLookupByLibrary.simpleMessage("Атрибути"),
    "secDiagnostics": MessageLookupByLibrary.simpleMessage("Діагностика"),
    "secParameters": MessageLookupByLibrary.simpleMessage("Параметри"),
    "secPolling": MessageLookupByLibrary.simpleMessage("Опитування"),
    "secPublish": MessageLookupByLibrary.simpleMessage("Що опублікує дерево"),
    "secRegister": MessageLookupByLibrary.simpleMessage("Регістр"),
    "secState": MessageLookupByLibrary.simpleMessage("Стан"),
    "secValue": MessageLookupByLibrary.simpleMessage("Значення"),
    "secWrite": MessageLookupByLibrary.simpleMessage("Запис"),
    "secretName": MessageLookupByLibrary.simpleMessage("Назва"),
    "secretValue": MessageLookupByLibrary.simpleMessage(
      "Значення (порожнє — видалити)",
    ),
    "secretsNote": MessageLookupByLibrary.simpleMessage(
      "Брокер запечатує секрет, і він більше не показується; лінк читає його за назвою.",
    ),
    "sectionEarlier": MessageLookupByLibrary.simpleMessage("Раніше"),
    "sectionNow": MessageLookupByLibrary.simpleMessage("Зараз"),
    "seeLinks": MessageLookupByLibrary.simpleMessage("див. Лінки"),
    "selectANode": MessageLookupByLibrary.simpleMessage(
      "Оберіть вузол у дереві.",
    ),
    "sessionExpired": MessageLookupByLibrary.simpleMessage("Сесія завершилася"),
    "setLogLevel": m154,
    "setLogLevelNote": MessageLookupByLibrary.simpleMessage(
      "Діє одразу, без перезапуску. Готується разом з іншими змінами.",
    ),
    "setPassword": MessageLookupByLibrary.simpleMessage("Задати пароль"),
    "setPasswordNote": MessageLookupByLibrary.simpleMessage(
      "Відкриті сесії лишаються до завершення.",
    ),
    "setPoll": MessageLookupByLibrary.simpleMessage("Задати опитування…"),
    "setRoles": MessageLookupByLibrary.simpleMessage("Задати ролі"),
    "setRolesNote": MessageLookupByLibrary.simpleMessage(
      "Ролі визначають, що доступно (див. Дозволи).",
    ),
    "setSecret": MessageLookupByLibrary.simpleMessage("Зберегти"),
    "setValue": MessageLookupByLibrary.simpleMessage("Задати значення"),
    "showPassword": MessageLookupByLibrary.simpleMessage("Показати пароль"),
    "signingIn": MessageLookupByLibrary.simpleMessage("Вхід…"),
    "siteRelayedBelow": MessageLookupByLibrary.simpleMessage(
      "Сайт, ретрансльований нижче",
    ),
    "sitesAround": m155,
    "sitesSubtitle": m156,
    "sizeBytes": m157,
    "sizeChars": m158,
    "sizeItems": m159,
    "sizeKeys": m160,
    "sizeLines": m161,
    "stage": MessageLookupByLibrary.simpleMessage("Підготувати"),
    "stagedActionNote": MessageLookupByLibrary.simpleMessage(
      "«Підготувати» додає дію до перегляду разом з іншими змінами.",
    ),
    "stagedChanges": m162,
    "stagedNote": MessageLookupByLibrary.simpleMessage(
      "Нічого не записується, доки ви не застосуєте. Кожна зміна виконується з вашими правами.",
    ),
    "stagedWas": m163,
    "stale": MessageLookupByLibrary.simpleMessage("застаріле"),
    "standbyAnswersAt": MessageLookupByLibrary.simpleMessage(
      "Його резервний gateway відповідає на",
    ),
    "standbyGateway": MessageLookupByLibrary.simpleMessage("Резервний gateway"),
    "standbyIs": m164,
    "stateConnected": MessageLookupByLibrary.simpleMessage("Під’єднано"),
    "stateFailed": MessageLookupByLibrary.simpleMessage("Збій"),
    "stateInstalled": MessageLookupByLibrary.simpleMessage("Встановлено"),
    "stateOffline": MessageLookupByLibrary.simpleMessage("Офлайн"),
    "stateStarting": MessageLookupByLibrary.simpleMessage("Запускається"),
    "stateStopped": MessageLookupByLibrary.simpleMessage("Зупинено"),
    "stateStopping": MessageLookupByLibrary.simpleMessage("Зупиняється"),
    "stateWaiting": MessageLookupByLibrary.simpleMessage("Чекає"),
    "stepBring": MessageLookupByLibrary.simpleMessage("Принести"),
    "stepCheck": MessageLookupByLibrary.simpleMessage("Перевірка"),
    "stepChecking": MessageLookupByLibrary.simpleMessage(
      "Перевірка користувача і пароля",
    ),
    "stepChoose": MessageLookupByLibrary.simpleMessage("Вибір"),
    "stepInstall": MessageLookupByLibrary.simpleMessage("Встановлення"),
    "stepOf": m165,
    "stepReaching": m166,
    "stepReading": MessageLookupByLibrary.simpleMessage(
      "Читання вашої ролі та сайтів",
    ),
    "stepWhere": MessageLookupByLibrary.simpleMessage("Де працює"),
    "studioAbout": m167,
    "studioSignedInHere": MessageLookupByLibrary.simpleMessage(
      "Studio увійшла сюди",
    ),
    "studioVersion": m168,
    "sysActiveNote": MessageLookupByLibrary.simpleMessage(
      "Обслуговує лінки, потоки, шлюз і сусідів. Відповідає на `sys/replication/**` для свого резерву.",
    ),
    "sysAdminOnly": MessageLookupByLibrary.simpleMessage("sys/**, лише admin"),
    "sysArbiterLease": MessageLookupByLibrary.simpleMessage("Оренда арбітра"),
    "sysAttnAcl": m169,
    "sysAttnAclDetail": m170,
    "sysAttnBehind": m171,
    "sysAttnBehindDetail": m172,
    "sysAttnBehindPlain": MessageLookupByLibrary.simpleMessage(
      "standby_lag більший за 0: перемикання зараз втратить записи",
    ),
    "sysAttnBroker": m173,
    "sysAttnBrokerPlain": MessageLookupByLibrary.simpleMessage("Нижчий брокер"),
    "sysAttnBrokerRelays": m174,
    "sysAttnFork": MessageLookupByLibrary.simpleMessage(
      "Резерв відклав розгалуження",
    ),
    "sysAttnLinkDetail": m175,
    "sysAttnLinkFailed": m176,
    "sysAttnNoStandby": MessageLookupByLibrary.simpleMessage(
      "За цим брокером не слідує резерв",
    ),
    "sysAttnNoStandbyDetail": MessageLookupByLibrary.simpleMessage(
      "standby_connected дорівнює 0",
    ),
    "sysAttnOpenAudit": MessageLookupByLibrary.simpleMessage(
      "Відкрити Аудит ›",
    ),
    "sysAttnOpenAvail": MessageLookupByLibrary.simpleMessage(
      "Відкрити Доступність ›",
    ),
    "sysAttnOpenLinks": MessageLookupByLibrary.simpleMessage(
      "Відкрити в Лінках ›",
    ),
    "sysAttnOpenQuarantine": MessageLookupByLibrary.simpleMessage(
      "Відкрити Карантин ›",
    ),
    "sysAttnOpenSites": MessageLookupByLibrary.simpleMessage(
      "Відкрити в Сайтах ›",
    ),
    "sysAttnQuarantine": m177,
    "sysAttnQuarantineDetail": m178,
    "sysAttnQuarantineSince": m179,
    "sysBackup": MessageLookupByLibrary.simpleMessage(
      "Резервна копія та відновлення",
    ),
    "sysBackupNote": m180,
    "sysBackupNoteNoSize": MessageLookupByLibrary.simpleMessage(
      "Усе, чим володіє брокер, лежить у його `data_dir`. Studio не робить резервних копій: вони містять ключі сайту, їх роблять на хості. Кроки, готові до копіювання:",
    ),
    "sysBackupWarning": MessageLookupByLibrary.simpleMessage(
      "Резервна копія містить CA сайту і ключ шлюзу: хто її читає, той адміністратор. Зашифруйте її і тримайте там, де читати можуть лише адміністратори брокера.",
    ),
    "sysBannerBehind": MessageLookupByLibrary.simpleMessage("Резерв відстає"),
    "sysBannerBoth": MessageLookupByLibrary.simpleMessage(
      "Резерв відстає і відклав розгалуження",
    ),
    "sysBannerFork": MessageLookupByLibrary.simpleMessage(
      "Резерв відклав розгалуження",
    ),
    "sysBannerForks": m181,
    "sysBannerLag": m182,
    "sysBrokerAll": MessageLookupByLibrary.simpleMessage("брокер (усе)"),
    "sysBrokerLogLevel": MessageLookupByLibrary.simpleMessage(
      "Рівень журналу брокера",
    ),
    "sysBytes": MessageLookupByLibrary.simpleMessage("Байти"),
    "sysClear": m183,
    "sysClearAsk": MessageLookupByLibrary.simpleMessage(
      "Очистити ці від’єднані лінки?",
    ),
    "sysClearAskBody": m184,
    "sysClearBoard": m185,
    "sysClearConfirm": MessageLookupByLibrary.simpleMessage("Очистити"),
    "sysClearFooter": MessageLookupByLibrary.simpleMessage(
      "`sys/~act/clear_conns` · config · питає перед запуском",
    ),
    "sysClearNone": MessageLookupByLibrary.simpleMessage(
      "Очистити від’єднані лінки…",
    ),
    "sysClearOne": MessageLookupByLibrary.simpleMessage(
      "Очистити 1 від’єднаний лінк…",
    ),
    "sysCleared": m186,
    "sysClearedNone": MessageLookupByLibrary.simpleMessage(
      "Брокер не вилучив жодного лінка.",
    ),
    "sysCmdBackup": MessageLookupByLibrary.simpleMessage(
      "Резервна копія (брокер зупинено)",
    ),
    "sysCmdBackupNote": MessageLookupByLibrary.simpleMessage(
      "Узгоджено й найпростіше. Зі знімком файлової системи (LVM, btrfs, ZFS) брокер може працювати далі.",
    ),
    "sysCmdCheck": MessageLookupByLibrary.simpleMessage(
      "Перед перезапуском зі зміненим файлом",
    ),
    "sysCmdCheckNote": MessageLookupByLibrary.simpleMessage(
      "Конфігурація розбирається і проходить перевірку; інакше код виходу 1.",
    ),
    "sysCmdVerify": MessageLookupByLibrary.simpleMessage("Перевірити копію"),
    "sysCmdVerifyNote": MessageLookupByLibrary.simpleMessage(
      "Перевіряє кожне сховище площини керування без запуску: CRC, ланцюг HMAC, якорі. Запустіть на відновленому data_dir перед стартом.",
    ),
    "sysCollecting": MessageLookupByLibrary.simpleMessage("Збираю…"),
    "sysCommandCopied": MessageLookupByLibrary.simpleMessage(
      "Команди скопійовано",
    ),
    "sysCopy": MessageLookupByLibrary.simpleMessage("Копіювати"),
    "sysCopyCommand": m187,
    "sysDownstream": MessageLookupByLibrary.simpleMessage("Нижчі брокери"),
    "sysElsewhere": MessageLookupByLibrary.simpleMessage(
      "Також налаштування брокера, що лежать там, де їх застосовують:",
    ),
    "sysElsewhereAccess": MessageLookupByLibrary.simpleMessage(
      "Ролі та права › Доступ",
    ),
    "sysElsewhereHistory": MessageLookupByLibrary.simpleMessage(
      "Зберігання та очищення › Історія",
    ),
    "sysElsewhereLinks": MessageLookupByLibrary.simpleMessage(
      "Допуск нових лінків › Лінки › Карантин",
    ),
    "sysElsewhereSites": MessageLookupByLibrary.simpleMessage(
      "Токени для нижчих сайтів › Сайти",
    ),
    "sysEvery5s": MessageLookupByLibrary.simpleMessage("кожні 5 с"),
    "sysFactLiveliness": MessageLookupByLibrary.simpleMessage("Живучість"),
    "sysFactSite": MessageLookupByLibrary.simpleMessage("Сайт"),
    "sysFilter": MessageLookupByLibrary.simpleMessage("Фільтр"),
    "sysFilterHint": MessageLookupByLibrary.simpleMessage(
      "текст у джерелі або повідомленні",
    ),
    "sysFlow": MessageLookupByLibrary.simpleMessage(
      "WAL, файли, сховище, історія",
    ),
    "sysForks": MessageLookupByLibrary.simpleMessage("Відкладені розгалуження"),
    "sysFrames": MessageLookupByLibrary.simpleMessage("Кадри"),
    "sysGetLog": MessageLookupByLibrary.simpleMessage("Отримати журнал"),
    "sysGroupLinks": MessageLookupByLibrary.simpleMessage("Лінки та сайти"),
    "sysGroupProcess": MessageLookupByLibrary.simpleMessage("Процес і диск"),
    "sysGuideCopied": m188,
    "sysGuideLink": MessageLookupByLibrary.simpleMessage(
      "Посібник: docs/operations.md › Warm standby ›",
    ),
    "sysHeld": MessageLookupByLibrary.simpleMessage("Що зберігає резерв"),
    "sysHeldControl": MessageLookupByLibrary.simpleMessage("Площина керування"),
    "sysHeldControlNote": MessageLookupByLibrary.simpleMessage(
      "Реєстр, визначення потоків і користувачі шлюзу: самі записи WAL, перевірені ланцюгом HMAC.",
    ),
    "sysHeldHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "sysHeldHistoryNote": MessageLookupByLibrary.simpleMessage(
      "Рядки кожної серії з журналу змін, записані у власні денні файли резерву.",
    ),
    "sysHeldSecrets": MessageLookupByLibrary.simpleMessage(
      "Секрети та дані лінків",
    ),
    "sysHeldSecretsNote": MessageLookupByLibrary.simpleMessage(
      "secrets.bin, токени лінків, data_dir лінків і пакети: запечатані частини по 1 MiB, файли до 64 MiB, вилучені, коли зникли тут.",
    ),
    "sysHeldStorage": MessageLookupByLibrary.simpleMessage("Сховище брокера"),
    "sysHeldStorageNote": MessageLookupByLibrary.simpleMessage(
      "Журнал змін сховища, застосований до власного сховища резерву (ціле дерево понад 20 000 змін).",
    ),
    "sysIn": MessageLookupByLibrary.simpleMessage("вхід"),
    "sysLag": MessageLookupByLibrary.simpleMessage("Відставання"),
    "sysLevelMore": MessageLookupByLibrary.simpleMessage("Рівень і суворіші"),
    "sysLines": MessageLookupByLibrary.simpleMessage("Рядків"),
    "sysLinkSource": m189,
    "sysLogCopied": m190,
    "sysLogLevelNote": MessageLookupByLibrary.simpleMessage(
      "Потрапляє до «Переглянути й застосувати»; після застосування діє одразу, без перезапуску, і замінює `RUST_LOG`. Zenoh лишається на warn нижче trace. Значення й токени не журналюються нижче trace. Власний рівень лінка: Лінки › лінк › Журнал.",
    ),
    "sysLogNeedsConfig": MessageLookupByLibrary.simpleMessage(
      "Журнал читають із рівнем config на sys.",
    ),
    "sysLogNotSaved": MessageLookupByLibrary.simpleMessage(
      "Не вдалося зберегти журнал",
    ),
    "sysLogSaved": m191,
    "sysLogSummary": m192,
    "sysLogSummaryNone": MessageLookupByLibrary.simpleMessage(
      "`sys/~act/get_log` · config",
    ),
    "sysMessages": MessageLookupByLibrary.simpleMessage("Повідомлення"),
    "sysMetaStarted": m193,
    "sysNeedsLook": m194,
    "sysNeedsLookNote": MessageLookupByLibrary.simpleMessage(
      "Зі значень самого брокера. Кожна картка відкриває екран, де це виправляють.",
    ),
    "sysNoLines": MessageLookupByLibrary.simpleMessage(
      "На цьому рівні рядків немає.",
    ),
    "sysNoProfiles": MessageLookupByLibrary.simpleMessage("Профілів немає."),
    "sysNoStale": MessageLookupByLibrary.simpleMessage(
      "Від’єднаних лінків немає.",
    ),
    "sysNoStandbyBody": MessageLookupByLibrary.simpleMessage(
      "`sys/standby_connected` дорівнює 0. Теплий резерв не налаштовано, або налаштований не досягає цього брокера. Якщо цей хост відмовить, сайт зупиниться, доки хост не повернеться; лінки на інших машинах перейдуть до наступної адреси, лише якщо її мають.",
    ),
    "sysNoStandbyStep1": MessageLookupByLibrary.simpleMessage(
      "1. Скопіюйте ключі на другий хост: `wyrmd keys export` тут, `wyrmd keys import` там.",
    ),
    "sysNoStandbyStep2": m195,
    "sysNoStandbyStep3": MessageLookupByLibrary.simpleMessage(
      "3. Запустіть другий хост; ця вкладка покаже його за секунду.",
    ),
    "sysNoStandbySteps": MessageLookupByLibrary.simpleMessage(
      "Щоб додати резерв (на хостах, не в Studio)",
    ),
    "sysNoStandbyTitle": MessageLookupByLibrary.simpleMessage(
      "За цим брокером не слідує жоден резерв",
    ),
    "sysNotConnected": MessageLookupByLibrary.simpleMessage("не з’єднано"),
    "sysNothing": MessageLookupByLibrary.simpleMessage(
      "Ніщо не потребує уваги.",
    ),
    "sysNothingToClear": MessageLookupByLibrary.simpleMessage(
      "Немає від’єднаних лінків для очищення",
    ),
    "sysNow": m196,
    "sysOfTotal": m197,
    "sysOpenAuditRecord": MessageLookupByLibrary.simpleMessage(
      "Відкрити запис аудиту ›",
    ),
    "sysOut": MessageLookupByLibrary.simpleMessage("вихід"),
    "sysPackages": MessageLookupByLibrary.simpleMessage("Пакети"),
    "sysProfileFile": m198,
    "sysProfileName": MessageLookupByLibrary.simpleMessage("Назва"),
    "sysProfileNameHint": MessageLookupByLibrary.simpleMessage(
      "<vendor>:<model>",
    ),
    "sysProfilePut": m199,
    "sysProfileRemoved": m200,
    "sysProfiles": MessageLookupByLibrary.simpleMessage("Профілі пристроїв"),
    "sysProfilesFooter": MessageLookupByLibrary.simpleMessage(
      "`sys/profiles` › Put Profile, Remove Profile · config",
    ),
    "sysProfilesNote": MessageLookupByLibrary.simpleMessage(
      "Моделі, які брокер віддає як `pub/<vendor>:<model>`: точки, одиниці та діапазони, що їх успадковують лінки й асистент.",
    ),
    "sysProfilesUnlisted": m201,
    "sysPulled": MessageLookupByLibrary.simpleMessage("забирає щосекунди"),
    "sysPut": MessageLookupByLibrary.simpleMessage("Додати профіль"),
    "sysPutProfile": MessageLookupByLibrary.simpleMessage("Додати профіль…"),
    "sysRecords": MessageLookupByLibrary.simpleMessage("записів"),
    "sysRemove": MessageLookupByLibrary.simpleMessage("Вилучити"),
    "sysRemoveProfile": m202,
    "sysRemoveProfileAsk": m203,
    "sysRunningActive": MessageLookupByLibrary.simpleMessage(
      "Працює · активний",
    ),
    "sysSaveLog": MessageLookupByLibrary.simpleMessage("Зберегти як .log"),
    "sysSecondsLeft": MessageLookupByLibrary.simpleMessage("с лишилось"),
    "sysSinceStart": MessageLookupByLibrary.simpleMessage("від запуску"),
    "sysSource": MessageLookupByLibrary.simpleMessage("Джерело"),
    "sysStale": MessageLookupByLibrary.simpleMessage("Від’єднані лінки"),
    "sysStaleNote": MessageLookupByLibrary.simpleMessage(
      "Лінки, допущені під час роботи, що працюють на інших машинах і зараз не з’єднані. Очищення вилучає їх із реєстру; їхні id вибувають і більше не можуть бути використані.",
    ),
    "sysStaleRow": m204,
    "sysStandbyBehind": MessageLookupByLibrary.simpleMessage(
      "Резерв · відстає",
    ),
    "sysStandbyConnected": MessageLookupByLibrary.simpleMessage(
      "Резерв з’єднано",
    ),
    "sysStandbyFollowing": MessageLookupByLibrary.simpleMessage(
      "Резерв · слідує",
    ),
    "sysStandbyNote": MessageLookupByLibrary.simpleMessage(
      "Ті самі ключі, власний `data_dir`. Перебирає роботу, лише коли цей брокер не відповідає, а свідок йому ще відповідає.",
    ),
    "sysSubAcl": MessageLookupByLibrary.simpleMessage(
      "від запуску маршрутизатора · відкрити Аудит",
    ),
    "sysSubAudit": MessageLookupByLibrary.simpleMessage(
      "хто що зробив · відкрити Аудит",
    ),
    "sysSubCpu": MessageLookupByLibrary.simpleMessage("100 = одне ядро"),
    "sysSubData": m205,
    "sysSubDisk": MessageLookupByLibrary.simpleMessage(
      "на файловій системі data_dir",
    ),
    "sysSubFollows": MessageLookupByLibrary.simpleMessage(
      "слідує за цим брокером через з’єднання сусідів",
    ),
    "sysSubForks": MessageLookupByLibrary.simpleMessage(
      "після усуненого розколу · аудит standby_forked",
    ),
    "sysSubForksNone": MessageLookupByLibrary.simpleMessage(
      "жодного розколу від запуску брокера",
    ),
    "sysSubLag": MessageLookupByLibrary.simpleMessage(
      "ще не на резерві: перемикання зараз їх втратить",
    ),
    "sysSubLagNone": MessageLookupByLibrary.simpleMessage(
      "резерв має всі записи реєстру",
    ),
    "sysSubLease": MessageLookupByLibrary.simpleMessage(
      "поновлює арбітр оренди",
    ),
    "sysSubLeaseLate": MessageLookupByLibrary.simpleMessage(
      "поновлюється пізно: перевірте хост арбітра",
    ),
    "sysSubLinkFailed": m206,
    "sysSubMemory": MessageLookupByLibrary.simpleMessage("резидентна"),
    "sysSubNoArbiter": MessageLookupByLibrary.simpleMessage(
      "арбітра не налаштовано",
    ),
    "sysSubOpenHistory": MessageLookupByLibrary.simpleMessage(
      "відкрити Історію",
    ),
    "sysSubOpenLinks": MessageLookupByLibrary.simpleMessage("відкрити Лінки"),
    "sysSubOpenQuarantine": MessageLookupByLibrary.simpleMessage(
      "відкрити Карантин",
    ),
    "sysSubOpenSites": MessageLookupByLibrary.simpleMessage("відкрити Сайти"),
    "sysSubPackages": MessageLookupByLibrary.simpleMessage(
      "встановлені пакети лінків",
    ),
    "sysSubPeer": m207,
    "sysSubSessions": MessageLookupByLibrary.simpleMessage(
      "мережеві сесії; користувачів шлюзу не враховано",
    ),
    "sysSubWaits": m208,
    "sysTabAvailability": MessageLookupByLibrary.simpleMessage("Доступність"),
    "sysTabLog": MessageLookupByLibrary.simpleMessage("Журнал"),
    "sysTabMaintenance": MessageLookupByLibrary.simpleMessage("Обслуговування"),
    "sysTabOverview": MessageLookupByLibrary.simpleMessage("Огляд"),
    "sysTabsLabel": MessageLookupByLibrary.simpleMessage("Розділи системи"),
    "sysThisActive": MessageLookupByLibrary.simpleMessage(
      "Цей брокер · активний",
    ),
    "sysThisBroker": MessageLookupByLibrary.simpleMessage("Цей брокер"),
    "sysTraffic": MessageLookupByLibrary.simpleMessage("Трафік маршрутизатора"),
    "sysTrafficDescribe": m209,
    "sysTrafficNote": MessageLookupByLibrary.simpleMessage(
      "Зібрано зі значень `sys`, поки Studio відкрито (брокер не зберігає їхньої історії). Лише мережеві сесії: вбудовані лінки та користувачі шлюзу працюють усередині процесу, їх не враховано.",
    ),
    "sysUnitConnected": MessageLookupByLibrary.simpleMessage("з’єднано"),
    "sysUnreachable": MessageLookupByLibrary.simpleMessage("Недосяжний"),
    "sysUpstream": MessageLookupByLibrary.simpleMessage("Вищі брокери"),
    "systemFooter": MessageLookupByLibrary.simpleMessage(
      "wyrmd.json5 задає початковий стан; усе, що змінено тут, живе в журналі попереднього запису.",
    ),
    "tabActions": MessageLookupByLibrary.simpleMessage("Дії"),
    "tabAudit": MessageLookupByLibrary.simpleMessage("Аудит"),
    "tabContents": MessageLookupByLibrary.simpleMessage("Вміст"),
    "tabGrants": MessageLookupByLibrary.simpleMessage("Дозволи"),
    "tabHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "tabParameters": MessageLookupByLibrary.simpleMessage("Параметри"),
    "tabPoints": MessageLookupByLibrary.simpleMessage("Точки"),
    "tabUsers": MessageLookupByLibrary.simpleMessage("Користувачі"),
    "tagNeeds": m210,
    "tagRunsNow": MessageLookupByLibrary.simpleMessage("виконується одразу"),
    "tagStaged": MessageLookupByLibrary.simpleMessage("готується"),
    "taskAwaiting": MessageLookupByLibrary.simpleMessage("чекає схвалення"),
    "taskDone": MessageLookupByLibrary.simpleMessage("виконано"),
    "taskFailed": MessageLookupByLibrary.simpleMessage(
      "не вдалося або зупинено",
    ),
    "taskListNote": m211,
    "taskPlanning": MessageLookupByLibrary.simpleMessage("планує"),
    "taskRunning": MessageLookupByLibrary.simpleMessage("виконує"),
    "thisBroker": MessageLookupByLibrary.simpleMessage("цей брокер"),
    "tlsCertificateOf": m212,
    "toAccept": MessageLookupByLibrary.simpleMessage("прийняти"),
    "toastDismiss": MessageLookupByLibrary.simpleMessage("Закрити"),
    "toastHidesIn": m213,
    "toastNotifications": MessageLookupByLibrary.simpleMessage("Сповіщення"),
    "toastStays": m214,
    "toastStream": MessageLookupByLibrary.simpleMessage(
      "Studio відкриє потоки знову, коли він повернеться.",
    ),
    "tokenForBelow": MessageLookupByLibrary.simpleMessage(
      "Токен для сайту нижче",
    ),
    "tokenHours": MessageLookupByLibrary.simpleMessage("Дійсний годин"),
    "tokenNote": MessageLookupByLibrary.simpleMessage(
      "Один токен одразу допускає брокер. Показується один раз; задайте кількість використань і години.",
    ),
    "tokenUses": MessageLookupByLibrary.simpleMessage("Використань"),
    "treeAction": MessageLookupByLibrary.simpleMessage("Дія"),
    "treeActionNote": MessageLookupByLibrary.simpleMessage(
      "блок, що запускає її, коли run when стає true; її аргументи — поля.",
    ),
    "treeActionNote2": MessageLookupByLibrary.simpleMessage(
      "блок, що її виконує: її параметри є полями, які заповнюють інші блоки, з тригером.",
    ),
    "treeEmpty": MessageLookupByLibrary.simpleMessage("Тут нічого немає."),
    "treeLoading": MessageLookupByLibrary.simpleMessage("Читаю дерево…"),
    "treeNoteLead": MessageLookupByLibrary.simpleMessage(
      "Дерево показує лише дані.",
    ),
    "treeNoteMiddle": MessageLookupByLibrary.simpleMessage("змінюється в"),
    "treeOf": m215,
    "treePoint": MessageLookupByLibrary.simpleMessage("Точка"),
    "treePointNote": MessageLookupByLibrary.simpleMessage(
      "на блоці: додає її як поле. На полотні: новий блок цього вузла.",
    ),
    "treePointNote2": MessageLookupByLibrary.simpleMessage(
      "на полотні: блок, що її читає (записувана точка питає «Читати» чи «Писати»; Alt пише). На полі: прив\'язується до нього.",
    ),
    "tryAgain": MessageLookupByLibrary.simpleMessage("Спробувати ще"),
    "turnOn": MessageLookupByLibrary.simpleMessage("Увімкнути"),
    "unbind": MessageLookupByLibrary.simpleMessage("Розв’язати"),
    "unitNumber": m216,
    "unpinField": MessageLookupByLibrary.simpleMessage("Відкріпити від блока"),
    "unreachableAdvice": MessageLookupByLibrary.simpleMessage(
      "Брокер, можливо, перезапускається, або цей комп’ютер в іншій мережі.",
    ),
    "unsubscribeNote": MessageLookupByLibrary.simpleMessage(
      "Точка більше не записується; рядки лишаються.",
    ),
    "upFor": m217,
    "updating": MessageLookupByLibrary.simpleMessage("Оновлення…"),
    "upstream": MessageLookupByLibrary.simpleMessage("вище"),
    "upstreamBroker": MessageLookupByLibrary.simpleMessage("Верхній брокер"),
    "upstreamFooter": MessageLookupByLibrary.simpleMessage(
      "Верхній із wyrmd.json5 змінюють там; доданий тут видаляють через sys/upstream/<name> ▸ Remove.",
    ),
    "useStandby": MessageLookupByLibrary.simpleMessage("Резервний gateway"),
    "user": MessageLookupByLibrary.simpleMessage("Користувач"),
    "userActive": MessageLookupByLibrary.simpleMessage("Активний"),
    "userDisabled": MessageLookupByLibrary.simpleMessage("Вимкнено"),
    "validate": MessageLookupByLibrary.simpleMessage("Перевірити"),
    "valueCopied": MessageLookupByLibrary.simpleMessage("Значення скопійовано"),
    "valuesDeployed": MessageLookupByLibrary.simpleMessage("розгорнута версія"),
    "valuesPreview": MessageLookupByLibrary.simpleMessage(
      "перегляд чернетки; нічого не записано",
    ),
    "versionDeployed": m218,
    "viaSite": m219,
    "viewValue": MessageLookupByLibrary.simpleMessage("Переглянути значення"),
    "viewerBadBool": MessageLookupByLibrary.simpleMessage("true або false"),
    "viewerBadJson": MessageLookupByLibrary.simpleMessage(
      "Не JSON-об’єкт і не список",
    ),
    "viewerBadNumber": MessageLookupByLibrary.simpleMessage("Не число"),
    "viewerEdit": MessageLookupByLibrary.simpleMessage("Редагувати"),
    "viewerEmpty": MessageLookupByLibrary.simpleMessage(
      "Порожньо: поле повернеться до типового значення",
    ),
    "viewerLockedBound": MessageLookupByLibrary.simpleMessage(
      "Лише читання: поле живить зв’язок. Розв’яжіть його, щоб ввести значення.",
    ),
    "viewerLockedInput": MessageLookupByLibrary.simpleMessage(
      "Лише читання: цей вхід не має введеного значення. Зв’яжіть з ним вихід.",
    ),
    "viewerLockedOutput": MessageLookupByLibrary.simpleMessage(
      "Лише читання: цей вихід обчислює блок.",
    ),
    "viewerSave": MessageLookupByLibrary.simpleMessage("Зберегти"),
    "viewerSaveHint": m220,
    "waitingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "Чекає в карантині",
    ),
    "waitingToBeLetIn": m221,
    "wasValue": m222,
    "wasWord": MessageLookupByLibrary.simpleMessage("було"),
    "watchGroup": MessageLookupByLibrary.simpleMessage("Група спостереження"),
    "watchGroups": m223,
    "welcomeUser": m224,
    "whatItRead": MessageLookupByLibrary.simpleMessage("Що прочитано"),
    "whyBring": MessageLookupByLibrary.simpleMessage(
      "Приносьте власний пакет лише тоді, коли його немає в офіційному списку. Zip, URL або Git-репозиторій зі зібраним пакетом, або один компонент.",
    ),
    "whyBroker": MessageLookupByLibrary.simpleMessage("Брокер"),
    "whyCheck": MessageLookupByLibrary.simpleMessage(
      "Перед встановленням перевіряються архів і вміст: розмір, шляхи, маніфест і його поля, версія протоколу, для яких хостів є бінарники.",
    ),
    "whyChoose": MessageLookupByLibrary.simpleMessage(
      "Більшість лінків — з офіційного списку: драйвер у wyrmd або пакет із вашого репозиторію. Власний пакет — лише якщо його там немає.",
    ),
    "whyDeauthorized": MessageLookupByLibrary.simpleMessage("Відкликано"),
    "whyFailed": MessageLookupByLibrary.simpleMessage(
      "Брокер відповів success: false. Його повідомлення пояснює чому.",
    ),
    "whyInstalled": MessageLookupByLibrary.simpleMessage(
      "Він працює, має власну ідентичність і оголосив свою гілку.",
    ),
    "whyInstalling": MessageLookupByLibrary.simpleMessage(
      "Це триває кілька секунд. Можна піти — встановлення продовжиться.",
    ),
    "whyNew": MessageLookupByLibrary.simpleMessage("Новий"),
    "whyRunCustom": MessageLookupByLibrary.simpleMessage(
      "Оберіть брокер. Лише брокери, для чийого хоста зібрано пакет, можуть його прийняти; спосіб роботи задає тип пакета.",
    ),
    "whyRunOfficial": MessageLookupByLibrary.simpleMessage(
      "Оберіть брокер, потім як лінк на ньому працюватиме. Вбудований драйвер може працювати в брокері, окремим процесом або на іншій машині.",
    ),
    "windowClose": MessageLookupByLibrary.simpleMessage("Закрити вікно"),
    "windowMaximize": MessageLookupByLibrary.simpleMessage("Розгорнути"),
    "windowMinimize": MessageLookupByLibrary.simpleMessage("Згорнути"),
    "windowRestore": MessageLookupByLibrary.simpleMessage("Відновити"),
    "wordOrderReason": MessageLookupByLibrary.simpleMessage(
      "Задається типом даних: суфіксом _wswap, _bswap або _wbswap.",
    ),
    "wouldRun": m225,
    "wouldSend": m226,
    "wouldWrite": m227,
    "writableNeeds": m228,
    "wrongPassword": MessageLookupByLibrary.simpleMessage(
      "Неправильний користувач або пароль. Попросіть адміністратора скинути пароль; gateway ніколи не надсилає його поштою.",
    ),
    "wsAccess": MessageLookupByLibrary.simpleMessage("Доступ"),
    "wsAssistant": MessageLookupByLibrary.simpleMessage("Асистент"),
    "wsExplorer": MessageLookupByLibrary.simpleMessage("Дерево"),
    "wsFlows": MessageLookupByLibrary.simpleMessage("Потоки"),
    "wsHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "wsLinks": MessageLookupByLibrary.simpleMessage("Лінки"),
    "wsSites": MessageLookupByLibrary.simpleMessage("Сайти"),
    "wsSystem": MessageLookupByLibrary.simpleMessage("Система"),
    "wyrmdOn": m229,
    "yes": MessageLookupByLibrary.simpleMessage("так"),
    "youTag": MessageLookupByLibrary.simpleMessage("ВИ"),
    "yourAnswers": MessageLookupByLibrary.simpleMessage("Ваші відповіді"),
    "yourAnswersNote": MessageLookupByLibrary.simpleMessage(
      "Ваші відповіді. Натисніть крок ліворуч, щоб змінити.",
    ),
    "yourUpstream": MessageLookupByLibrary.simpleMessage("ваш верхній"),
    "zipFile": MessageLookupByLibrary.simpleMessage("Zip-файл"),
  };
}

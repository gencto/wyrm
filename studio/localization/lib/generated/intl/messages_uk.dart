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

  static String m0(n) => "${n} д тому";

  static String m1(n) => "${n} год тому";

  static String m2(n) => "${n} хв тому";

  static String m3(n) => "просить приєднатися · ретранслює ${n}";

  static String m4(sites) => "просить ретранслювати: ${sites}";

  static String m5(n) =>
      "${Intl.plural(n, one: '${n} блок', few: '${n} блоки', other: '${n} блоків')}";

  static String m6(brokers, devices) =>
      "${brokers} брокерів · ${devices} пристроїв";

  static String m7(driver) => "вбудований драйвер ${driver}";

  static String m8(site) => "підписано CA · ${site} CA";

  static String m9(site) =>
      "${site} під’єднується до нього; там авторизують ${site}.";

  static String m10(id) => "Відкликати допуск ${id}?";

  static String m11(device) =>
      "Працює на ${device}; брокер не може його запустити чи зупинити.";

  static String m12(id) => "Параметри ${id}";

  static String m13(when) => "уперше ${when}";

  static String m14(v) => "v${v} розгорнуто";

  static String m15(v) => "v${v} · помилка";

  static String m16(v) => "v${v} зупинено";

  static String m17(v) => "Версія ${v}";

  static String m18(site) => "Потоки на ${site}";

  static String m19(address) => "з ${address}";

  static String m20(key) => "Перейти до ${key}";

  static String m21(id) => "Доступ для ${id}";

  static String m22(id) => "Історія параметрів ${id}";

  static String m23(name, broker) => "${name} встановлено на ${broker}.";

  static String m24(n) =>
      "${Intl.plural(n, one: 'уже ${n} лінк', few: 'уже ${n} лінки', other: 'уже ${n} лінків')}";

  static String m25(site) =>
      "Запускає і стежить ${site}: вбудовані драйвери і встановлені пакети. Їх можна зупинити, змінити, оновити й видалити.";

  static String m26(site) => "Лінки на ${site}";

  static String m27(id) => "Журнал ${id}";

  static String m28(level, have) => "Потрібно ${level} · у вас ${have}";

  static String m29(level) => "Потрібно ${level} · у вас є";

  static String m30(site) => "немає: ${site} — вершина";

  static String m31(site) => "Дерево покаже wy/${site}.";

  static String m32(name) => "пакет ${name}";

  static String m33(n) =>
      "${Intl.plural(n, zero: 'без параметрів', one: '${n} параметр', few: '${n} параметри', other: '${n} параметрів')}";

  static String m34(rev) => "Параметри (ревізія ${rev}, JSON)";

  static String m35(name) => "${name} встановлено";

  static String m36(name) => "Встановлення ${name}…";

  static String m37(cn) => "Відхилити ${cn}?";

  static String m38(n) =>
      "${Intl.plural(n, one: 'ретранслює ${n} сайт', few: 'ретранслює ${n} сайти', other: 'ретранслює ${n} сайтів')}";

  static String m39(id) => "Видалити ${id}?";

  static String m40(action) => "Результат · ${action}";

  static String m41(what) => "повертає ${what}";

  static String m42(rev) => "Ревізія ${rev}";

  static String m43(rev) => "Ревізія ${rev} · діє";

  static String m44(rev) => "Повернути ревізію ${rev}?";

  static String m45(n) =>
      "${Intl.plural(n, one: '${n} рядок', few: '${n} рядки', other: '${n} рядків')}";

  static String m46(user) =>
      "Виконується як ${user}. Нічого більше в дереві не змінюється, якщо результат не використати.";

  static String m47(site) => "Працює на ${site}";

  static String m48(site) => "Сайти навколо ${site}";

  static String m49(site) =>
      "До чого під’єднаний ${site} і що під’єднано до нього: брокери вище й нижче, платформи, куди він надсилає, і пристрої, чиї лінки працюють поза брокером.";

  static String m50(count) =>
      "${Intl.plural(count, zero: 'Немає підготовлених змін', one: '${count} підготовлена зміна', few: '${count} підготовлені зміни', other: '${count} підготовлених змін')}";

  static String m51(n, total) => "Крок ${n} з ${total}";

  static String m52(level) => "потрібно ${level}";

  static String m53(site) => "Дерево · ${site}";

  static String m54(site) => "через ${site}";

  static String m55(n, who) => "${n} чекають на допуск: ${who}";

  static String m56(value) => "було ${value}";

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
    "addALink": MessageLookupByLibrary.simpleMessage("Додати лінк"),
    "addAnother": MessageLookupByLibrary.simpleMessage("Додати ще"),
    "agoDays": m0,
    "agoHours": m1,
    "agoMinutes": m2,
    "agoNow": MessageLookupByLibrary.simpleMessage("щойно"),
    "allowAllLinks": MessageLookupByLibrary.simpleMessage(
      "Допускати всі лінки",
    ),
    "allowAllLinksNote": MessageLookupByLibrary.simpleMessage(
      "Кожен новий CN цього CA одразу стає лінком, без схвалення. Витеклий сертифікат теж пройде.",
    ),
    "answerBroker": MessageLookupByLibrary.simpleMessage("Брокер"),
    "answerFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "answerLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "answerName": MessageLookupByLibrary.simpleMessage("Назва"),
    "answerRights": MessageLookupByLibrary.simpleMessage("Права"),
    "answerRuns": MessageLookupByLibrary.simpleMessage("Працює"),
    "appTitle": MessageLookupByLibrary.simpleMessage("WYRM Studio"),
    "apply": MessageLookupByLibrary.simpleMessage("Застосувати"),
    "approve": MessageLookupByLibrary.simpleMessage("Схвалити"),
    "approveBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення допускає його як брокер нижче з указаними ретрансляціями. Спершу порівняйте ключ із його sys/upstream/<цей сайт>/key.",
    ),
    "approveLinkNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення робить його зовнішнім лінком із власною гілкою і токеном; скопіюйте токен на пристрій. Роутер перезавантажується приблизно на секунду. Відхилення відмовляє цьому CN надалі.",
    ),
    "asksToJoin": MessageLookupByLibrary.simpleMessage("просить приєднатися"),
    "asksToJoinRelays": m3,
    "asksToRelay": m4,
    "back": MessageLookupByLibrary.simpleMessage("Назад"),
    "backToLinks": MessageLookupByLibrary.simpleMessage("До лінків"),
    "block": MessageLookupByLibrary.simpleMessage("Блок"),
    "blocksCount": m5,
    "branchOrTag": MessageLookupByLibrary.simpleMessage("гілка або тег"),
    "bringOne": MessageLookupByLibrary.simpleMessage(
      "Оберіть файл або вкажіть, де пакет.",
    ),
    "brokerRefused": MessageLookupByLibrary.simpleMessage(
      "Брокер відхилив зміну; наступні не застосовано.",
    ),
    "brokerSays": MessageLookupByLibrary.simpleMessage("Брокер каже"),
    "brokerWaiting": MessageLookupByLibrary.simpleMessage("Брокер чекає"),
    "brokersDevices": m6,
    "builtIn": MessageLookupByLibrary.simpleMessage("вбудований"),
    "builtInDriver": m7,
    "builtInSummary": MessageLookupByLibrary.simpleMessage(
      "Вбудований у wyrmd · нічого не завантажується",
    ),
    "caSigned": m8,
    "canDoNothing": MessageLookupByLibrary.simpleMessage(
      "нічого: ні читання, ні запису",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Скасувати"),
    "cannotReachGateway": MessageLookupByLibrary.simpleMessage(
      "Не вдалося з’єднатися з gateway",
    ),
    "catalogNote": MessageLookupByLibrary.simpleMessage(
      "Вбудований: у wyrmd, нічого не завантажується. Пакет: з індексу packages.repository, SHA-256 перевіряється; брокер показує лише пакети, які може встановити.",
    ),
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
    "chooseWasm": MessageLookupByLibrary.simpleMessage(
      "Оберіть компонент .wasm",
    ),
    "chooseZip": MessageLookupByLibrary.simpleMessage("Оберіть пакет .zip"),
    "colCertificate": MessageLookupByLibrary.simpleMessage("Сертифікат"),
    "colDeployedBy": MessageLookupByLibrary.simpleMessage("Хто розгорнув"),
    "colFlow": MessageLookupByLibrary.simpleMessage("Потік"),
    "colFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "colLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "colLinkDevice": MessageLookupByLibrary.simpleMessage("Лінк · пристрій"),
    "colMode": MessageLookupByLibrary.simpleMessage("Режим"),
    "colPoint": MessageLookupByLibrary.simpleMessage("Точка"),
    "colQuality": MessageLookupByLibrary.simpleMessage("Якість"),
    "colReadsWrites": MessageLookupByLibrary.simpleMessage("Читає → пише"),
    "colRunsAs": MessageLookupByLibrary.simpleMessage("Працює як"),
    "colState": MessageLookupByLibrary.simpleMessage("Стан"),
    "colTime": MessageLookupByLibrary.simpleMessage("Час"),
    "colType": MessageLookupByLibrary.simpleMessage("Тип"),
    "colValue": MessageLookupByLibrary.simpleMessage("Значення"),
    "colVersionSource": MessageLookupByLibrary.simpleMessage(
      "Версія · джерело",
    ),
    "colWho": MessageLookupByLibrary.simpleMessage("Хто"),
    "colWhyHere": MessageLookupByLibrary.simpleMessage("Чому тут"),
    "colWrite": MessageLookupByLibrary.simpleMessage("Запис"),
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
    "connectNote": m9,
    "connectUpstream": MessageLookupByLibrary.simpleMessage(
      "Під’єднати до верхнього",
    ),
    "continueLabel": MessageLookupByLibrary.simpleMessage("Далі"),
    "couldNotConnectToInternet": MessageLookupByLibrary.simpleMessage(
      "Не вдалося підключитися до інтернету.",
    ),
    "customPackage": MessageLookupByLibrary.simpleMessage("Власний пакет"),
    "customPackageNote": MessageLookupByLibrary.simpleMessage(
      "Архів пакета, який ви приносите: zip, URL, Git-репозиторій або один .wasm. Перевіряється перед встановленням.",
    ),
    "darkTheme": MessageLookupByLibrary.simpleMessage("Темна тема"),
    "dataflow": MessageLookupByLibrary.simpleMessage("Потік даних"),
    "deauthorizeBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Його права тут забрано зараз, наступне з’єднання чекатиме в карантині. Його сайти лишаються під ним.",
    ),
    "deauthorizeTitle": m10,
    "decideInLinks": MessageLookupByLibrary.simpleMessage("Вирішити в Лінках"),
    "decideInLinksNote": MessageLookupByLibrary.simpleMessage(
      "Лінк у карантині схвалюють або відхиляють у Лінках › Карантин.",
    ),
    "decideInSites": MessageLookupByLibrary.simpleMessage("вирішіть у Сайтах"),
    "deploy": MessageLookupByLibrary.simpleMessage("Розгорнути"),
    "deploying": MessageLookupByLibrary.simpleMessage("Розгортання…"),
    "designGallery": MessageLookupByLibrary.simpleMessage("Галерея дизайну"),
    "discard": MessageLookupByLibrary.simpleMessage("Скасувати все"),
    "doneOnTheDevice": m11,
    "doneOnTheDeviceUpgrade": MessageLookupByLibrary.simpleMessage(
      "Хто керує пристроєм, той і оновлює його; він перепідключиться з тим самим сертифікатом.",
    ),
    "downstream": MessageLookupByLibrary.simpleMessage("нижче"),
    "downstreamBroker": MessageLookupByLibrary.simpleMessage("Брокер нижче"),
    "downstreamBrokerQuic": MessageLookupByLibrary.simpleMessage(
      "брокер нижче · через quic",
    ),
    "draftValid": MessageLookupByLibrary.simpleMessage(
      "Чернетка · правильна, не розгорнута",
    ),
    "editDataflow": MessageLookupByLibrary.simpleMessage("Редагувати потік"),
    "editDataflowNote": MessageLookupByLibrary.simpleMessage(
      "Відкрити в редакторі; нічого не змінюється до розгортання.",
    ),
    "editParamsNote": MessageLookupByLibrary.simpleMessage(
      "«Підготувати» застосовується з іншими змінами; лінк перезапуститься з новою ревізією.",
    ),
    "editParamsOf": m12,
    "factAbout": MessageLookupByLibrary.simpleMessage("Про"),
    "factAllowConfig": MessageLookupByLibrary.simpleMessage("Config від нього"),
    "factBelow": MessageLookupByLibrary.simpleMessage("Нижче"),
    "factBlocks": MessageLookupByLibrary.simpleMessage("Блоки"),
    "factBranch": MessageLookupByLibrary.simpleMessage("Гілка"),
    "factCanDo": MessageLookupByLibrary.simpleMessage("Може"),
    "factCertificate": MessageLookupByLibrary.simpleMessage("Сертифікат"),
    "factDevice": MessageLookupByLibrary.simpleMessage("Пристрій"),
    "factFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "factHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "factKey": MessageLookupByLibrary.simpleMessage("Ключ"),
    "factKind": MessageLookupByLibrary.simpleMessage("Тип"),
    "factProblem": MessageLookupByLibrary.simpleMessage("Проблема"),
    "factRelays": MessageLookupByLibrary.simpleMessage("Ретранслює"),
    "factRunning": MessageLookupByLibrary.simpleMessage("Працює"),
    "factRunsAs": MessageLookupByLibrary.simpleMessage("Працює як"),
    "factSeen": MessageLookupByLibrary.simpleMessage("Побачено"),
    "factStatus": MessageLookupByLibrary.simpleMessage("Стан"),
    "factThrough": MessageLookupByLibrary.simpleMessage("Через"),
    "factTree": MessageLookupByLibrary.simpleMessage("Дерево"),
    "factUpstreams": MessageLookupByLibrary.simpleMessage("Верхні"),
    "factVersion": MessageLookupByLibrary.simpleMessage("Версія"),
    "failed": MessageLookupByLibrary.simpleMessage("не пройшов"),
    "firstSeen": m13,
    "fixFirst": MessageLookupByLibrary.simpleMessage(
      "Чернетка не проходить перевірку.",
    ),
    "flowDeployed": m14,
    "flowError": m15,
    "flowName": MessageLookupByLibrary.simpleMessage("Ідентифікатор потоку"),
    "flowPropertiesNote": MessageLookupByLibrary.simpleMessage(
      "Кожне поле має значення, вхід і вихід. Введіть значення або натисніть вихід, а потім вхід, щоб зв’язати; подвійне натискання на вхід розв’язує. Перетягуйте блоки з палітри, точки — з Дерева.",
    ),
    "flowStopped": m16,
    "flowVersion": m17,
    "flowsFooter": MessageLookupByLibrary.simpleMessage(
      "Розгортання потребує config на dataflows; gateway додає ваші докази для кожної цілі. Глядачі можуть лише дивитися.",
    ),
    "flowsOn": m18,
    "flowsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Кожен потік працює в брокері. Ви редагуєте чернетку; нічого не змінюється до розгортання.",
    ),
    "fromAddress": m19,
    "fromTheOfficialList": MessageLookupByLibrary.simpleMessage(
      "З офіційного списку",
    ),
    "gatewayUrl": MessageLookupByLibrary.simpleMessage("URL gateway"),
    "gatewayUrlHint": MessageLookupByLibrary.simpleMessage(
      "http://host:8445 або кілька через кому",
    ),
    "gitRef": MessageLookupByLibrary.simpleMessage("Ref"),
    "gitRepository": MessageLookupByLibrary.simpleMessage(
      "Git-репозиторій (HTTPS)",
    ),
    "goTo": m20,
    "goUp": MessageLookupByLibrary.simpleMessage("Вгору"),
    "grantFor": m21,
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
    "historyOf": m22,
    "holdUnknown": MessageLookupByLibrary.simpleMessage(
      "Тримати невідомі з’єднання тут",
    ),
    "holdUnknownNote": MessageLookupByLibrary.simpleMessage(
      "Вимкнено (і «Допускати всі» вимкнено): невідомі сертифікати ігноруються.",
    ),
    "howItRunsThere": MessageLookupByLibrary.simpleMessage("Як він там працює"),
    "install": MessageLookupByLibrary.simpleMessage("Встановити"),
    "installRailNote": MessageLookupByLibrary.simpleMessage(
      "Встановлення потребує config на sys (роль admin). Нічого не встановлюється, доки ви не натиснете «Встановити».",
    ),
    "installedOn": m23,
    "invalidGatewayUrl": MessageLookupByLibrary.simpleMessage(
      "Це не URL gateway (http:// або https:// і хост)",
    ),
    "issue": MessageLookupByLibrary.simpleMessage("Видати"),
    "legendConnected": MessageLookupByLibrary.simpleMessage("під’єднано"),
    "legendOffline": MessageLookupByLibrary.simpleMessage("офлайн"),
    "legendPlatform": MessageLookupByLibrary.simpleMessage("платформа"),
    "legendWaiting": MessageLookupByLibrary.simpleMessage("чекає в карантині"),
    "letItIn": MessageLookupByLibrary.simpleMessage("Допустити"),
    "letOthersIn": MessageLookupByLibrary.simpleMessage("Допустити інших"),
    "letTheBrokerIn": MessageLookupByLibrary.simpleMessage("Допустити брокер"),
    "lightTheme": MessageLookupByLibrary.simpleMessage("Світла тема"),
    "linkName": MessageLookupByLibrary.simpleMessage("Назва лінка"),
    "linkOverTls": MessageLookupByLibrary.simpleMessage("лінк · через tls"),
    "linksAlready": m24,
    "linksLocalNote": m25,
    "linksOn": m26,
    "linksQuarantineNote": MessageLookupByLibrary.simpleMessage(
      "З’єднання із сертифікатом цього сайту, для яких немає лінка. Вони нічого не читають і не пишуть, доки ви їх не схвалите.",
    ),
    "linksRemoteNote": MessageLookupByLibrary.simpleMessage(
      "Вони працюють на своїх машинах і під’єднуються із сертифікатом цього сайту. Ви вирішуєте, що їм доступно і чи лишаються вони; сам пристрій оновлюють там, де він працює.",
    ),
    "linksSubtitle": MessageLookupByLibrary.simpleMessage(
      "Лінками на цьому брокері ви керуєте повністю. Лінки на інших пристроях ви лише допускаєте, обмежуєте або відключаєте.",
    ),
    "loading": MessageLookupByLibrary.simpleMessage("Завантаження…"),
    "logEmpty": MessageLookupByLibrary.simpleMessage("Рядків немає."),
    "logIn": MessageLookupByLibrary.simpleMessage("Увійти"),
    "logInSubtitle": MessageLookupByLibrary.simpleMessage(
      "Увійдіть у gateway WYRM.",
    ),
    "logOf": m27,
    "logOut": MessageLookupByLibrary.simpleMessage("Вийти"),
    "manifest": MessageLookupByLibrary.simpleMessage("Маніфест"),
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
    "needsLevelYouHave": m28,
    "needsLevelYouHaveIt": m29,
    "networkError": MessageLookupByLibrary.simpleMessage(
      "Проблема зі з’єднанням",
    ),
    "newCertificate": MessageLookupByLibrary.simpleMessage("новий сертифікат"),
    "newDataflow": MessageLookupByLibrary.simpleMessage("Новий потік"),
    "newValue": MessageLookupByLibrary.simpleMessage("Нове значення"),
    "no": MessageLookupByLibrary.simpleMessage("ні"),
    "noFlows": MessageLookupByLibrary.simpleMessage(
      "На цьому сайті ще немає потоків.",
    ),
    "noHistory": MessageLookupByLibrary.simpleMessage(
      "Немає записаних значень у цьому проміжку. Точку записує спостереження в sys/history.",
    ),
    "noLocalLinks": MessageLookupByLibrary.simpleMessage(
      "На цьому брокері ще немає лінків. Додайте лінк, щоб під’єднати пристрій.",
    ),
    "noPoints": MessageLookupByLibrary.simpleMessage(
      "Тут немає значень. Відкрийте гілку в дереві.",
    ),
    "noRemoteLinks": MessageLookupByLibrary.simpleMessage(
      "Жоден пристрій не під’єднаний як зовнішній лінк.",
    ),
    "noRevisions": MessageLookupByLibrary.simpleMessage("Ревізій немає."),
    "noUpstream": m30,
    "noValue": MessageLookupByLibrary.simpleMessage("немає значення"),
    "noneAsked": MessageLookupByLibrary.simpleMessage("не запитано"),
    "notDeployed": MessageLookupByLibrary.simpleMessage("не розгорнуто"),
    "notInstalled": MessageLookupByLibrary.simpleMessage(
      "Брокер не встановив його.",
    ),
    "notRecorded": MessageLookupByLibrary.simpleMessage("не записується"),
    "notWritable": MessageLookupByLibrary.simpleMessage(
      "Лише читання: драйвер не приймає тут значення.",
    ),
    "nothingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "У карантині нічого не чекає.",
    ),
    "nothingStaged": MessageLookupByLibrary.simpleMessage(
      "Нічого не підготовлено. Змініть значення або параметр.",
    ),
    "nothingToDeploy": MessageLookupByLibrary.simpleMessage(
      "Нічого не змінилося після останнього розгортання.",
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
    "openItsTree": MessageLookupByLibrary.simpleMessage("Відкрити його дерево"),
    "openItsTreeNote": m31,
    "operateRunsNow": MessageLookupByLibrary.simpleMessage(
      "Керування · виконується одразу",
    ),
    "operateRunsNowNote": MessageLookupByLibrary.simpleMessage(
      "Виконується на пристрої з вашими правами і записується в аудит.",
    ),
    "package": MessageLookupByLibrary.simpleMessage("пакет"),
    "packageNamed": m32,
    "packageSummary": MessageLookupByLibrary.simpleMessage(
      "Пакет із вашого репозиторію · SHA-256 звіряється з індексом під час завантаження",
    ),
    "packageUrl": MessageLookupByLibrary.simpleMessage("URL пакета (HTTPS)"),
    "paletteBlocks": MessageLookupByLibrary.simpleMessage("Блоки"),
    "paletteTree": MessageLookupByLibrary.simpleMessage("Дерево"),
    "paramCount": m33,
    "paramsJson": m34,
    "paramsNote": MessageLookupByLibrary.simpleMessage(
      "~meta вузла, як його оголошує брокер: профіль, cfg і attr.",
    ),
    "passed": MessageLookupByLibrary.simpleMessage("пройшов"),
    "password": MessageLookupByLibrary.simpleMessage("Пароль"),
    "pickOne": MessageLookupByLibrary.simpleMessage("Оберіть лінк зі списку."),
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
    "pointsNote": MessageLookupByLibrary.simpleMessage(
      "Значення оновлюються наживо. Зміни готуються в цій сесії; нічого не записується до застосування.",
    ),
    "qCheckFailed": MessageLookupByLibrary.simpleMessage(
      "Пакет не пройшов перевірку",
    ),
    "qCheckOk": MessageLookupByLibrary.simpleMessage(
      "Пакет виглядає правильно",
    ),
    "qChoose": MessageLookupByLibrary.simpleMessage("Що ви хочете додати?"),
    "qFailed": MessageLookupByLibrary.simpleMessage("Брокер не встановив його"),
    "qInstalled": m35,
    "qInstalling": m36,
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
    "recorded": MessageLookupByLibrary.simpleMessage("записується"),
    "refresh": MessageLookupByLibrary.simpleMessage("Оновити"),
    "reject": MessageLookupByLibrary.simpleMessage("Відхилити"),
    "rejectNote": MessageLookupByLibrary.simpleMessage(
      "Цей сертифікат надалі відхилятиметься.",
    ),
    "rejectTitle": m37,
    "relayedFooter": MessageLookupByLibrary.simpleMessage(
      "Звідси нічого робити: він прийшов разом зі своїм ретранслятором. Відкличте ретранслятор, щоб відрізати його.",
    ),
    "relaysSites": m38,
    "remoteFooter": MessageLookupByLibrary.simpleMessage(
      "Якщо пристрій втрачено або вкрадено: «Видалити назавжди». Відкликання — це пауза: схваліть знову з карантину, і він збереже ім’я та дерево.",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("Видалити"),
    "removeBlock": MessageLookupByLibrary.simpleMessage("Видалити блок"),
    "removeDeletesTree": MessageLookupByLibrary.simpleMessage(
      "Його буде зупинено, дерево видалено. Ім’я можна використати знову.",
    ),
    "removeLinkTitle": m39,
    "removeRetiresId": MessageLookupByLibrary.simpleMessage(
      "Його буде зупинено, дерево видалено, а id вилучено: його не можна використати знову.",
    ),
    "requiredField": MessageLookupByLibrary.simpleMessage("Обов’язкове поле"),
    "resultOf": m40,
    "returns": m41,
    "review": MessageLookupByLibrary.simpleMessage("Перегляд"),
    "reviewAndApply": MessageLookupByLibrary.simpleMessage(
      "Переглянути й застосувати",
    ),
    "revision": m42,
    "revisionNow": m43,
    "rightsNote": MessageLookupByLibrary.simpleMessage(
      "Без цього брокер нічого не встановить. Доступи змінюються пізніше через «Надати доступ», інше — параметрами лінка.",
    ),
    "rightsTitle": MessageLookupByLibrary.simpleMessage(
      "Пакет просить такі права",
    ),
    "rollBack": MessageLookupByLibrary.simpleMessage("Повернути"),
    "rollBackNote": MessageLookupByLibrary.simpleMessage(
      "Ці параметри стануть новою ревізією, і лінк перезапуститься з ними.",
    ),
    "rollBackTo": m44,
    "rowsAnswered": m45,
    "runNow": MessageLookupByLibrary.simpleMessage("Виконати"),
    "runNowNote": m46,
    "runsOn": m47,
    "runsOnAnotherDevice": MessageLookupByLibrary.simpleMessage(
      "Працює на іншому пристрої",
    ),
    "sameCallCli": MessageLookupByLibrary.simpleMessage(
      "Той самий виклик з CLI",
    ),
    "searchHint": MessageLookupByLibrary.simpleMessage(
      "Перейти до вузла, дії або лінка",
    ),
    "searchLinks": MessageLookupByLibrary.simpleMessage("Шукати у списку"),
    "secretName": MessageLookupByLibrary.simpleMessage("Назва"),
    "secretValue": MessageLookupByLibrary.simpleMessage(
      "Значення (порожнє — видалити)",
    ),
    "secretsNote": MessageLookupByLibrary.simpleMessage(
      "Брокер запечатує секрет, і він більше не показується; лінк читає його за назвою.",
    ),
    "selectANode": MessageLookupByLibrary.simpleMessage(
      "Оберіть вузол у дереві.",
    ),
    "sessionExpired": MessageLookupByLibrary.simpleMessage("Сесія завершилася"),
    "setSecret": MessageLookupByLibrary.simpleMessage("Зберегти"),
    "setValue": MessageLookupByLibrary.simpleMessage("Задати значення"),
    "siteRelayedBelow": MessageLookupByLibrary.simpleMessage(
      "Сайт, ретрансльований нижче",
    ),
    "sitesAround": m48,
    "sitesSubtitle": m49,
    "somethingWentWrong": MessageLookupByLibrary.simpleMessage(
      "Щось пішло не так",
    ),
    "stage": MessageLookupByLibrary.simpleMessage("Підготувати"),
    "stagedActionNote": MessageLookupByLibrary.simpleMessage(
      "«Підготувати» додає дію до перегляду разом з іншими змінами.",
    ),
    "stagedChanges": m50,
    "stagedNote": MessageLookupByLibrary.simpleMessage(
      "Нічого не записується, доки ви не застосуєте. Кожна зміна виконується з вашими правами.",
    ),
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
    "stepChoose": MessageLookupByLibrary.simpleMessage("Вибір"),
    "stepInstall": MessageLookupByLibrary.simpleMessage("Встановлення"),
    "stepOf": m51,
    "stepWhere": MessageLookupByLibrary.simpleMessage("Де працює"),
    "studioSignedInHere": MessageLookupByLibrary.simpleMessage(
      "Studio увійшла сюди",
    ),
    "tabActions": MessageLookupByLibrary.simpleMessage("Дії"),
    "tabHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "tabParameters": MessageLookupByLibrary.simpleMessage("Параметри"),
    "tabPoints": MessageLookupByLibrary.simpleMessage("Точки"),
    "tagNeeds": m52,
    "tagRunsNow": MessageLookupByLibrary.simpleMessage("виконується одразу"),
    "tagStaged": MessageLookupByLibrary.simpleMessage("готується"),
    "thisBroker": MessageLookupByLibrary.simpleMessage("цей брокер"),
    "toAccept": MessageLookupByLibrary.simpleMessage("прийняти"),
    "tokenForBelow": MessageLookupByLibrary.simpleMessage(
      "Токен для сайту нижче",
    ),
    "tokenHours": MessageLookupByLibrary.simpleMessage("Дійсний годин"),
    "tokenNote": MessageLookupByLibrary.simpleMessage(
      "Один токен одразу допускає брокер. Показується один раз; задайте кількість використань і години.",
    ),
    "tokenUses": MessageLookupByLibrary.simpleMessage("Використань"),
    "treeNote": MessageLookupByLibrary.simpleMessage(
      "Клацніть правою кнопкою або натисніть і утримуйте вузол, щоб побачити дії. sys/** змінюється в Лінках, Доступі, Сайтах і Системі.",
    ),
    "treeOf": m53,
    "tryAgainLater": MessageLookupByLibrary.simpleMessage("Спробуйте пізніше."),
    "upstream": MessageLookupByLibrary.simpleMessage("вище"),
    "upstreamBroker": MessageLookupByLibrary.simpleMessage("Верхній брокер"),
    "upstreamFooter": MessageLookupByLibrary.simpleMessage(
      "Верхній із wyrmd.json5 змінюють там; доданий тут видаляють через sys/upstream/<name> ▸ Remove.",
    ),
    "user": MessageLookupByLibrary.simpleMessage("Користувач"),
    "validate": MessageLookupByLibrary.simpleMessage("Перевірити"),
    "viaSite": m54,
    "waitingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "Чекає в карантині",
    ),
    "waitingToBeLetIn": m55,
    "wasValue": m56,
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
    "wsAccess": MessageLookupByLibrary.simpleMessage("Доступ"),
    "wsAssistant": MessageLookupByLibrary.simpleMessage("Асистент"),
    "wsExplorer": MessageLookupByLibrary.simpleMessage("Дерево"),
    "wsFlows": MessageLookupByLibrary.simpleMessage("Потоки"),
    "wsHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "wsLinks": MessageLookupByLibrary.simpleMessage("Лінки"),
    "wsSites": MessageLookupByLibrary.simpleMessage("Сайти"),
    "wsSystem": MessageLookupByLibrary.simpleMessage("Система"),
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

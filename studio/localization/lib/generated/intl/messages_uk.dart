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

  static String m3(sites) => "просить ретранслювати: ${sites}";

  static String m4(driver) => "вбудований драйвер ${driver}";

  static String m5(site) => "підписано CA · ${site} CA";

  static String m6(id) => "Відкликати допуск ${id}?";

  static String m7(device) =>
      "Працює на ${device}; брокер не може його запустити чи зупинити.";

  static String m8(id) => "Параметри ${id}";

  static String m9(when) => "уперше ${when}";

  static String m10(address) => "з ${address}";

  static String m11(key) => "Перейти до ${key}";

  static String m12(id) => "Доступ для ${id}";

  static String m13(id) => "Історія параметрів ${id}";

  static String m14(site) =>
      "Запускає і стежить ${site}: вбудовані драйвери і встановлені пакети. Їх можна зупинити, змінити, оновити й видалити.";

  static String m15(site) => "Лінки на ${site}";

  static String m16(id) => "Журнал ${id}";

  static String m17(level, have) => "Потрібно ${level} · у вас ${have}";

  static String m18(level) => "Потрібно ${level} · у вас є";

  static String m19(name) => "пакет ${name}";

  static String m20(rev) => "Параметри (ревізія ${rev}, JSON)";

  static String m21(cn) => "Відхилити ${cn}?";

  static String m22(id) => "Видалити ${id}?";

  static String m23(rev) => "Ревізія ${rev}";

  static String m24(rev) => "Ревізія ${rev} · діє";

  static String m25(rev) => "Повернути ревізію ${rev}?";

  static String m26(site) => "Працює на ${site}";

  static String m27(count) =>
      "${Intl.plural(count, zero: 'Немає підготовлених змін', one: '${count} підготовлена зміна', few: '${count} підготовлені зміни', other: '${count} підготовлених змін')}";

  static String m28(site) => "через ${site}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "_locale": MessageLookupByLibrary.simpleMessage("uk"),
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
    "appTitle": MessageLookupByLibrary.simpleMessage("WYRM Studio"),
    "apply": MessageLookupByLibrary.simpleMessage("Застосувати"),
    "approve": MessageLookupByLibrary.simpleMessage("Схвалити"),
    "approveBrokerNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення допускає його як брокер нижче з указаними ретрансляціями. Спершу порівняйте ключ із його sys/upstream/<цей сайт>/key.",
    ),
    "approveLinkNote": MessageLookupByLibrary.simpleMessage(
      "Схвалення робить його зовнішнім лінком із власною гілкою і токеном; скопіюйте токен на пристрій. Роутер перезавантажується приблизно на секунду. Відхилення відмовляє цьому CN надалі.",
    ),
    "asksToRelay": m3,
    "brokerRefused": MessageLookupByLibrary.simpleMessage(
      "Брокер відхилив зміну; наступні не застосовано.",
    ),
    "builtInDriver": m4,
    "caSigned": m5,
    "canDoNothing": MessageLookupByLibrary.simpleMessage(
      "нічого: ні читання, ні запису",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Скасувати"),
    "cannotReachGateway": MessageLookupByLibrary.simpleMessage(
      "Не вдалося з’єднатися з gateway",
    ),
    "checkYourConnection": MessageLookupByLibrary.simpleMessage(
      "Перевірте з’єднання та спробуйте ще раз.",
    ),
    "colCertificate": MessageLookupByLibrary.simpleMessage("Сертифікат"),
    "colFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "colLink": MessageLookupByLibrary.simpleMessage("Лінк"),
    "colLinkDevice": MessageLookupByLibrary.simpleMessage("Лінк · пристрій"),
    "colMode": MessageLookupByLibrary.simpleMessage("Режим"),
    "colRunsAs": MessageLookupByLibrary.simpleMessage("Працює як"),
    "colState": MessageLookupByLibrary.simpleMessage("Стан"),
    "colVersionSource": MessageLookupByLibrary.simpleMessage(
      "Версія · джерело",
    ),
    "colWho": MessageLookupByLibrary.simpleMessage("Хто"),
    "colWhyHere": MessageLookupByLibrary.simpleMessage("Чому тут"),
    "couldNotConnectToInternet": MessageLookupByLibrary.simpleMessage(
      "Не вдалося підключитися до інтернету.",
    ),
    "darkTheme": MessageLookupByLibrary.simpleMessage("Темна тема"),
    "deauthorizeTitle": m6,
    "decideInSites": MessageLookupByLibrary.simpleMessage("вирішіть у Сайтах"),
    "designGallery": MessageLookupByLibrary.simpleMessage("Галерея дизайну"),
    "discard": MessageLookupByLibrary.simpleMessage("Скасувати все"),
    "doneOnTheDevice": m7,
    "doneOnTheDeviceUpgrade": MessageLookupByLibrary.simpleMessage(
      "Хто керує пристроєм, той і оновлює його; він перепідключиться з тим самим сертифікатом.",
    ),
    "downstreamBrokerQuic": MessageLookupByLibrary.simpleMessage(
      "брокер нижче · через quic",
    ),
    "editParamsNote": MessageLookupByLibrary.simpleMessage(
      "«Підготувати» застосовується з іншими змінами; лінк перезапуститься з новою ревізією.",
    ),
    "editParamsOf": m8,
    "factBranch": MessageLookupByLibrary.simpleMessage("Гілка"),
    "factCanDo": MessageLookupByLibrary.simpleMessage("Може"),
    "factCertificate": MessageLookupByLibrary.simpleMessage("Сертифікат"),
    "factDevice": MessageLookupByLibrary.simpleMessage("Пристрій"),
    "factFrom": MessageLookupByLibrary.simpleMessage("Звідки"),
    "factKey": MessageLookupByLibrary.simpleMessage("Ключ"),
    "factKind": MessageLookupByLibrary.simpleMessage("Тип"),
    "factRelays": MessageLookupByLibrary.simpleMessage("Ретранслює"),
    "factRunsAs": MessageLookupByLibrary.simpleMessage("Працює як"),
    "factSeen": MessageLookupByLibrary.simpleMessage("Побачено"),
    "factVersion": MessageLookupByLibrary.simpleMessage("Версія"),
    "firstSeen": m9,
    "fromAddress": m10,
    "gatewayUrl": MessageLookupByLibrary.simpleMessage("URL gateway"),
    "gatewayUrlHint": MessageLookupByLibrary.simpleMessage(
      "http://host:8445 або кілька через кому",
    ),
    "goTo": m11,
    "grantFor": m12,
    "grantLevel": MessageLookupByLibrary.simpleMessage("Рівень"),
    "grantPath": MessageLookupByLibrary.simpleMessage("Ключ або шаблон"),
    "groupChange": MessageLookupByLibrary.simpleMessage("Змінити"),
    "groupOnTheDevice": MessageLookupByLibrary.simpleMessage(
      "Робиться на пристрої, не тут",
    ),
    "groupRemove": MessageLookupByLibrary.simpleMessage("Видалити"),
    "groupRun": MessageLookupByLibrary.simpleMessage("Робота"),
    "groupVersion": MessageLookupByLibrary.simpleMessage("Версія"),
    "groupYouControl": MessageLookupByLibrary.simpleMessage(
      "Що ви контролюєте тут",
    ),
    "historyOf": m13,
    "holdUnknown": MessageLookupByLibrary.simpleMessage(
      "Тримати невідомі з’єднання тут",
    ),
    "holdUnknownNote": MessageLookupByLibrary.simpleMessage(
      "Вимкнено (і «Допускати всі» вимкнено): невідомі сертифікати ігноруються.",
    ),
    "invalidGatewayUrl": MessageLookupByLibrary.simpleMessage(
      "Це не URL gateway (http:// або https:// і хост)",
    ),
    "letItIn": MessageLookupByLibrary.simpleMessage("Допустити"),
    "letTheBrokerIn": MessageLookupByLibrary.simpleMessage("Допустити брокер"),
    "lightTheme": MessageLookupByLibrary.simpleMessage("Світла тема"),
    "linkOverTls": MessageLookupByLibrary.simpleMessage("лінк · через tls"),
    "linksLocalNote": m14,
    "linksOn": m15,
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
    "logOf": m16,
    "logOut": MessageLookupByLibrary.simpleMessage("Вийти"),
    "modeEmbedded": MessageLookupByLibrary.simpleMessage("Вбудований"),
    "modeExternal": MessageLookupByLibrary.simpleMessage("Зовнішній"),
    "modeProcess": MessageLookupByLibrary.simpleMessage("Процес"),
    "more": MessageLookupByLibrary.simpleMessage("Ще"),
    "needsLevelYouHave": m17,
    "needsLevelYouHaveIt": m18,
    "networkError": MessageLookupByLibrary.simpleMessage(
      "Проблема зі з’єднанням",
    ),
    "noLocalLinks": MessageLookupByLibrary.simpleMessage(
      "На цьому брокері ще немає лінків. Додайте лінк, щоб під’єднати пристрій.",
    ),
    "noRemoteLinks": MessageLookupByLibrary.simpleMessage(
      "Жоден пристрій не під’єднаний як зовнішній лінк.",
    ),
    "noRevisions": MessageLookupByLibrary.simpleMessage("Ревізій немає."),
    "nothingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "У карантині нічого не чекає.",
    ),
    "nothingStaged": MessageLookupByLibrary.simpleMessage(
      "Нічого не підготовлено. Змініть значення або параметр.",
    ),
    "offline": MessageLookupByLibrary.simpleMessage(
      "З’єднання з gateway втрачено. Перепідключення; на екрані останні отримані значення.",
    ),
    "ok": MessageLookupByLibrary.simpleMessage("OK"),
    "onOtherDevices": MessageLookupByLibrary.simpleMessage(
      "На інших пристроях",
    ),
    "onThisBroker": MessageLookupByLibrary.simpleMessage("На цьому брокері"),
    "packageNamed": m19,
    "paramsJson": m20,
    "password": MessageLookupByLibrary.simpleMessage("Пароль"),
    "pleaseCheckYourNetworkSettings": MessageLookupByLibrary.simpleMessage(
      "Перевірте налаштування мережі.",
    ),
    "pleaseLogInAgain": MessageLookupByLibrary.simpleMessage(
      "Увійдіть ще раз.",
    ),
    "quarantine": MessageLookupByLibrary.simpleMessage("Карантин"),
    "refresh": MessageLookupByLibrary.simpleMessage("Оновити"),
    "reject": MessageLookupByLibrary.simpleMessage("Відхилити"),
    "rejectNote": MessageLookupByLibrary.simpleMessage(
      "Цей сертифікат надалі відхилятиметься.",
    ),
    "rejectTitle": m21,
    "remoteFooter": MessageLookupByLibrary.simpleMessage(
      "Якщо пристрій втрачено або вкрадено: «Видалити назавжди». Відкликання — це пауза: схваліть знову з карантину, і він збереже ім’я та дерево.",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("Видалити"),
    "removeDeletesTree": MessageLookupByLibrary.simpleMessage(
      "Його буде зупинено, дерево видалено. Ім’я можна використати знову.",
    ),
    "removeLinkTitle": m22,
    "removeRetiresId": MessageLookupByLibrary.simpleMessage(
      "Його буде зупинено, дерево видалено, а id вилучено: його не можна використати знову.",
    ),
    "requiredField": MessageLookupByLibrary.simpleMessage("Обов’язкове поле"),
    "review": MessageLookupByLibrary.simpleMessage("Перегляд"),
    "reviewAndApply": MessageLookupByLibrary.simpleMessage(
      "Переглянути й застосувати",
    ),
    "revision": m23,
    "revisionNow": m24,
    "rollBack": MessageLookupByLibrary.simpleMessage("Повернути"),
    "rollBackNote": MessageLookupByLibrary.simpleMessage(
      "Ці параметри стануть новою ревізією, і лінк перезапуститься з ними.",
    ),
    "rollBackTo": m25,
    "runsOn": m26,
    "runsOnAnotherDevice": MessageLookupByLibrary.simpleMessage(
      "Працює на іншому пристрої",
    ),
    "searchHint": MessageLookupByLibrary.simpleMessage(
      "Перейти до вузла, дії або лінка",
    ),
    "secretName": MessageLookupByLibrary.simpleMessage("Назва"),
    "secretValue": MessageLookupByLibrary.simpleMessage(
      "Значення (порожнє — видалити)",
    ),
    "secretsNote": MessageLookupByLibrary.simpleMessage(
      "Брокер запечатує секрет, і він більше не показується; лінк читає його за назвою.",
    ),
    "sessionExpired": MessageLookupByLibrary.simpleMessage("Сесія завершилася"),
    "setSecret": MessageLookupByLibrary.simpleMessage("Зберегти"),
    "somethingWentWrong": MessageLookupByLibrary.simpleMessage(
      "Щось пішло не так",
    ),
    "stage": MessageLookupByLibrary.simpleMessage("Підготувати"),
    "stagedChanges": m27,
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
    "thisBroker": MessageLookupByLibrary.simpleMessage("цей брокер"),
    "tryAgainLater": MessageLookupByLibrary.simpleMessage("Спробуйте пізніше."),
    "upstream": MessageLookupByLibrary.simpleMessage("вище"),
    "user": MessageLookupByLibrary.simpleMessage("Користувач"),
    "viaSite": m28,
    "waitingInQuarantine": MessageLookupByLibrary.simpleMessage(
      "Чекає в карантині",
    ),
    "whyBroker": MessageLookupByLibrary.simpleMessage("Брокер"),
    "whyDeauthorized": MessageLookupByLibrary.simpleMessage("Відкликано"),
    "whyNew": MessageLookupByLibrary.simpleMessage("Новий"),
    "wsAccess": MessageLookupByLibrary.simpleMessage("Доступ"),
    "wsAssistant": MessageLookupByLibrary.simpleMessage("Асистент"),
    "wsExplorer": MessageLookupByLibrary.simpleMessage("Дерево"),
    "wsFlows": MessageLookupByLibrary.simpleMessage("Потоки"),
    "wsHistory": MessageLookupByLibrary.simpleMessage("Історія"),
    "wsLinks": MessageLookupByLibrary.simpleMessage("Лінки"),
    "wsSites": MessageLookupByLibrary.simpleMessage("Сайти"),
    "wsSystem": MessageLookupByLibrary.simpleMessage("Система"),
  };
}

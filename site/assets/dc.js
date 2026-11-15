// A small renderer for the interactive install page.
//
// The page's markup lives in <template id="view">. It holds:
//   {{a.b}}                          a dotted lookup into renderVals()
//   <template data-for="xs" data-as="x">  one copy per item of xs
//   <template data-if="flag">        shown while flag is truthy
//   onclick="{{fn}}" / oninput="{{fn}}" / onchange="{{fn}}"  handlers
//   disabled="{{flag}}"              present only while flag is truthy
// A Component (extends DCLogic) keeps state; setState renders the page again.
(function () {
  'use strict';

  const HOLE = /\{\{\s*([\w.]+)\s*\}\}/g;
  const ONE = /^\{\{\s*([\w.]+)\s*\}\}$/;
  const BOOLEAN = new Set(['disabled', 'checked', 'hidden', 'readonly', 'required']);

  function lookup(scope, path) {
    let v = scope;
    for (const k of path.split('.')) {
      if (v == null) return undefined;
      v = v[k];
    }
    return v;
  }

  function text(scope, s) {
    return s.replace(HOLE, (_, p) => {
      const v = lookup(scope, p);
      return v == null ? '' : String(v);
    });
  }

  function renderChildren(from, scope, into) {
    for (const child of from.childNodes) {
      const out = render(child, scope);
      if (out) into.appendChild(out);
    }
  }

  function render(node, scope) {
    if (node.nodeType === Node.TEXT_NODE) {
      return document.createTextNode(text(scope, node.nodeValue));
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return null;

    if (node.localName === 'template' && node.dataset.for) {
      const frag = document.createDocumentFragment();
      const list = lookup(scope, node.dataset.for) || [];
      for (const item of list) {
        renderChildren(node.content, Object.assign(Object.create(scope), { [node.dataset.as]: item }), frag);
      }
      return frag;
    }
    if (node.localName === 'template' && node.dataset.if) {
      const frag = document.createDocumentFragment();
      if (lookup(scope, node.dataset.if)) renderChildren(node.content, scope, frag);
      return frag;
    }

    const el = node.cloneNode(false);
    for (const attr of Array.from(node.attributes)) {
      const name = attr.name;
      const one = attr.value.match(ONE);
      if (name.startsWith('on') && one) {
        el.removeAttribute(name);
        const fn = lookup(scope, one[1]);
        // A text field's change runs on every keystroke, as in the design.
        const type = name === 'onchange' && el.localName === 'input' ? 'input' : name.slice(2);
        if (typeof fn === 'function') el.addEventListener(type, fn);
      } else if (BOOLEAN.has(name) && one) {
        if (lookup(scope, one[1])) el.setAttribute(name, '');
        else el.removeAttribute(name);
      } else if (attr.value.indexOf('{{') >= 0) {
        const v = text(scope, attr.value);
        if (name === 'value' && el.localName === 'input') el.value = v;
        el.setAttribute(name, v);
      }
    }
    renderChildren(node.localName === 'template' ? node.content : node, scope, el.localName === 'template' ? el.content : el);
    return el;
  }

  class DCLogic {
    constructor(props) {
      this.props = props || {};
      this.state = {};
    }
    setState(patch) {
      this.state = Object.assign({}, this.state, patch);
      if (this._paint) this._paint();
    }
    renderVals() {
      return {};
    }
  }

  function mount(Component, props) {
    const view = document.getElementById('view');
    const app = document.getElementById('app');
    const c = new Component(props);
    c._paint = () => {
      // Keep focus (and the caret of a text field) where it was.
      const FOCUSABLE = 'a[href], button, input, select, textarea';
      const a = document.activeElement;
      const focus = a && app.contains(a)
        ? { i: Array.from(app.querySelectorAll(FOCUSABLE)).indexOf(a), s: a.selectionStart, e: a.selectionEnd }
        : null;
      const x = window.scrollX, y = window.scrollY;
      const frag = document.createDocumentFragment();
      renderChildren(view.content, c.renderVals(), frag);
      app.replaceChildren(frag);
      if (focus) {
        const el = app.querySelectorAll(FOCUSABLE)[focus.i];
        if (el) {
          el.focus({ preventScroll: true });
          if (typeof focus.s === 'number' && el.setSelectionRange) el.setSelectionRange(focus.s, focus.e);
        }
      }
      window.scrollTo(x, y);
    };
    c._paint();
    if (location.hash) {
      const t = document.getElementById(location.hash.slice(1));
      if (t) t.scrollIntoView();
    }
    return c;
  }

  window.DCLogic = DCLogic;
  window.DC = { mount };
})();

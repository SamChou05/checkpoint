#!/usr/bin/env node
'use strict';
// One isolated native observation. All executed JavaScript below is app-owned.
// Input HTML/properties are data; there is no eval or model-supplied script API.
const fs = require('fs');
const crypto = require('crypto');
const PROTOCOL = 'checkpoint.html_artifact_job.v1';
const OBSERVATION_PROTOCOL = 'checkpoint.html_artifact_observation.v1';
const PROPERTIES = ['disabled', "matches(':disabled')", 'required', 'readOnly', 'willValidate', 'validity.valueMissing', 'validity.valid', 'checkValidity()'];
const SETTINGS = {offline: true, javaScriptEnabled: false, acceptDownloads: false, serviceWorkers: 'block', allRoutesAborted: true, chromiumSandbox: true};
const TAGS = ['form', 'fieldset', 'legend', 'label', 'input', 'button', 'textarea', 'select', 'option', 'optgroup', 'div', 'span', 'p', 'br'];
const ATTRIBUTES = ['id', 'type', 'value', 'name', 'disabled', 'required', 'readonly', 'checked', 'multiple', 'selected', 'min', 'max', 'step', 'minlength', 'maxlength', 'pattern', 'for', 'form', 'placeholder', 'label', 'size'];
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const length = value => [...value].length;
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']' : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}' : JSON.stringify(value);
const fail = reason => { throw new Error(reason); };
const object = (value, keys) => { if (value === null || Array.isArray(value) || typeof value !== 'object' || canonical(Object.keys(value).sort()) !== canonical([...keys].sort())) fail('invalid_object_fields'); };
const text = (value, maximum, minimum = 1) => {
  if (typeof value !== 'string' || length(value.trim()) < minimum || length(value) > maximum || [...value].some(c => /[\p{Cs}\p{Cf}]/u.test(c) || (/\p{Cc}/u.test(c) && !'\n\r\t'.includes(c)))) fail('invalid_or_oversized_text');
};
function readInput() {
  const chunks = []; let bytes = 0;
  while (true) {
    const buffer = Buffer.alloc(4096), count = fs.readSync(0, buffer, 0, buffer.length, null);
    if (!count) break;
    bytes += count;
    if (bytes > 16384) fail('input_byte_limit_exceeded');
    chunks.push(buffer.subarray(0, count));
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
function validateJob(job) {
  object(job, ['protocol', 'spec', 'prompt', 'choices', 'artifact_sha256', 'probe_sha256', 'observer_source_sha256', 'job_id']);
  const s = job.spec;
  object(s, ['html', 'targetID', 'properties', 'alternatives', 'explanation', 'topic', 'difficulty']);
  text(s.html, 320);
  if (typeof s.targetID !== 'string' || !/^[A-Za-z][A-Za-z0-9_-]{0,23}$/.test(s.targetID)) fail('invalid_target_id');
  if (!Array.isArray(s.properties) || s.properties.length < 2 || s.properties.length > 4 || s.properties.some(p => !PROPERTIES.includes(p)) || new Set(s.properties).size !== s.properties.length) fail('invalid_properties');
  if (!Array.isArray(s.alternatives) || s.alternatives.length !== 4) fail('four_alternatives_required');
  for (const alternative of s.alternatives) {
    object(alternative, ['values', 'reason']);
    if (!Array.isArray(alternative.values) || alternative.values.length !== s.properties.length || alternative.values.some(v => typeof v !== 'boolean')) fail('invalid_boolean_tuple');
    text(alternative.reason, 280, 12);
  }
  text(s.explanation, 420, 12); text(s.topic, 80);
  if (!Number.isInteger(s.difficulty) || s.difficulty < 1 || s.difficulty > 5) fail('invalid_proposed_difficulty');
  const prompt = `In a fresh Chromium document, for #${s.targetID}, what are ${s.properties.join(', ')} (in order)?\n${s.html}`;
  const choices = s.alternatives.map(a => '[' + a.values.join(', ') + ']');
  if (length(prompt) > 320 || choices.some(c => length(c) > 140) || new Set(choices).size !== 4) fail('display_limit_or_duplicate_choice');
  if (job.protocol !== PROTOCOL || job.prompt !== prompt || canonical(job.choices) !== canonical(choices) || job.artifact_sha256 !== hash(s.html) || job.probe_sha256 !== hash(canonical({targetID: s.targetID, properties: s.properties})) || job.observer_source_sha256 !== hash(fs.readFileSync(__filename))) fail('job_binding_mismatch');
  const unsigned = {...job}; delete unsigned.job_id;
  if (job.job_id !== hash(canonical(unsigned))) fail('job_id_mismatch');
}
function bounded(promise, milliseconds) {
  let timer;
  return Promise.race([promise, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('local_operation_deadline')), milliseconds); })]).finally(() => clearTimeout(timer));
}
async function main() {
  let job, browser, context;
  const result = {
    protocol: OBSERVATION_PROTOCOL, job_id: null, artifact_sha256: null, probe_sha256: null,
    observer_source_sha256: hash(fs.readFileSync(__filename)), status: 'operational_failure', reason: '',
    browser: {name: 'chromium', version: ''}, settings: SETTINGS, values: null,
    serialized_dom: '', serialized_dom_sha256: '', target_outer_html: '',
    cleanup: {context: 'not_created', browser: 'not_created'},
  };
  try {
    job = readInput(); validateJob(job);
    for (const key of ['job_id', 'artifact_sha256', 'probe_sha256']) result[key] = job[key];
    const {chromium} = require(process.env.CHECKPOINT_PLAYWRIGHT_MODULE || 'playwright');
    // A fresh managed browser, never a user's browser/profile. Do not pass AWS or
    // other application credentials into the browser process environment.
    const browserEnv = Object.fromEntries(['PATH', 'HOME', 'TMPDIR', 'LANG'].filter(k => process.env[k] !== undefined).map(k => [k, process.env[k]]));
    result.cleanup.browser = 'launch_unconfirmed';
    browser = await chromium.launch({headless: true, chromiumSandbox: true, timeout: 10000, env: browserEnv});
    result.cleanup.browser = 'open';
    const browserVersion = browser.version();
    text(browserVersion, 80);
    result.browser.version = browserVersion;
    result.cleanup.context = 'creation_unconfirmed';
    context = await bounded(browser.newContext({offline: true, javaScriptEnabled: false, acceptDownloads: false, serviceWorkers: 'block'}), 3000);
    result.cleanup.context = 'open';
    await bounded(context.route('**/*', route => route.abort()), 3000);
    const page = await bounded(context.newPage(), 3000);
    // Parse in an inert template first: unsupported elements/attributes never
    // enter the active document. The model cannot supply observer expressions.
    const passive = await bounded(page.evaluate(({html, tags, attributes}) => {
      const template = document.createElement('template');
      template.innerHTML = html;
      return [...template.content.querySelectorAll('*')].every(el => el.namespaceURI === 'http://www.w3.org/1999/xhtml' && tags.includes(el.localName) && [...el.attributes].every(a => attributes.includes(a.name)));
    }, {html: job.spec.html, tags: TAGS, attributes: ATTRIBUTES}), 3000);
    if (!passive) { result.status = 'unsupported'; fail('unsupported_tag_or_attribute'); }
    await page.setContent(job.spec.html, {timeout: 3000, waitUntil: 'domcontentloaded'});
    const observed = await bounded(page.evaluate(({targetID, properties, tags, attributes}) => {
      const allowed = [...document.querySelectorAll('*')].every(el => el.namespaceURI === 'http://www.w3.org/1999/xhtml' && (['html', 'head', 'body'].includes(el.localName) || tags.includes(el.localName)) && [...el.attributes].every(a => attributes.includes(a.name)));
      const ids = [...document.querySelectorAll('[id]')].map(el => el.id);
      const targets = [...document.querySelectorAll('[id]')].filter(el => el.id === targetID);
      if (!allowed || new Set(ids).size !== ids.length || targets.length !== 1) return {reason: 'unsupported_dom_or_target'};
      const target = targets[0];
      if (!['input', 'button', 'textarea', 'select'].includes(target.localName)) return {reason: 'unsupported_target_element'};
      const values = properties.map(property => {
        switch (property) {
          case 'disabled': return target.disabled;
          case "matches(':disabled')": return target.matches(':disabled');
          case 'required': return target.required;
          case 'readOnly': return target.readOnly;
          case 'willValidate': return target.willValidate;
          case 'validity.valueMissing': return target.validity.valueMissing;
          case 'validity.valid': return target.validity.valid;
          case 'checkValidity()': return target.checkValidity();
          default: return undefined;
        }
      });
      if (values.some(v => typeof v !== 'boolean')) return {reason: 'property_not_boolean_on_target'};
      return {values, targetOuterHTML: target.outerHTML, dom: document.documentElement.outerHTML};
    }, {targetID: job.spec.targetID, properties: job.spec.properties, tags: TAGS, attributes: ATTRIBUTES}), 3000);
    if (observed.reason) { result.status = 'unsupported'; fail(observed.reason); }
    if (length(observed.dom) > 4096 || length(observed.targetOuterHTML) > 4096) fail('native_capture_limit_exceeded');
    result.values = observed.values;
    result.serialized_dom = observed.dom;
    result.serialized_dom_sha256 = hash(observed.dom);
    result.target_outer_html = observed.targetOuterHTML;
    result.status = 'observed';
  } catch (error) {
    // Preserve bounded operational diagnostics, never environment or stack text.
    const known = /^(invalid_|unsupported_|missing_|duplicate_|unbalanced_|four_|display_|job_|input_|local_|native_|property_)/.test(error.message || '');
    result.reason = known ? String(error.message).slice(0, 160) : String(error.name || 'Error').slice(0, 80);
  } finally {
    for (const [name, resource] of [['context', context], ['browser', browser]]) {
      if (!resource) continue;
      try { await bounded(resource.close(), 3000); result.cleanup[name] = 'closed'; }
      catch (_) { result.cleanup[name] = 'failed'; result.status = 'operational_failure'; result.reason = 'cleanup_failed'; }
    }
  }
  let encoded = JSON.stringify(result) + '\n';
  if (Buffer.byteLength(encoded, 'utf8') > 32768) {
    result.status = 'operational_failure'; result.reason = 'output_byte_limit_exceeded';
    result.serialized_dom = ''; result.target_outer_html = ''; result.values = null;
    encoded = JSON.stringify(result) + '\n';
  }
  // An isolated single-job CLI. A parent should also enforce a process deadline;
  // a failed cleanup is explicit and must never produce an admitted question.
  process.stdout.write(encoded, () => process.exit(result.status === 'observed' ? 0 : 1));
}
main().catch(() => { process.exitCode = 1; });

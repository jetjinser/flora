// SPDX-FileCopyrightText: 2026 Jinser Kafka <aimer@purejs.icu>
//
// SPDX-License-Identifier: GPL-3.0-or-later

const readline = require('node:readline');
const temml = require('temml');

const macros = { '\\mbox': '\\text{#1}' };
const input = readline.createInterface({ input: process.stdin });

input.on('line', line => {
  const separator = line.indexOf('\t');
  if (separator < 0) {
    process.stdout.write('ERR\tinvalid request\n');
    return;
  }

  const displayMode = line.slice(0, separator) === 'd';
  const source = Buffer.from(line.slice(separator + 1), 'hex').toString('utf8');
  try {
    const mathml = temml.renderToString(source, {
      displayMode,
      throwOnError: true,
      macros,
    }).replace(/[\r\n]+/g, ' ');
    process.stdout.write(`OK\t${mathml}\n`);
  } catch (error) {
    const message = String(error.message || error).replace(/[\r\n\t]+/g, ' ');
    process.stdout.write(`ERR\t${message}\n`);
  }
});

import { before, expect, test } from './session-fixtures';
import { waitForGridInteractive } from './test-utils';

test.beforeEach(before);

test('schema-backed JSON table bodies show readable prose and labeled checkbox states', async ({
  page,
}, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.waitForFunction(
    () =>
      window.store?.getClientDb()?.isReady === true &&
      window.store?.getSyncStatus().serverConnected === true,
  );

  // Invented records and an ordinary Property schema. Resolve the same nested
  // local references used by schema-backed imported values, through real saves.
  const created = await page.evaluate(async () => {
    const store = window.store;
    const drive = store.getDrive();
    const name = 'https://atomicdata.dev/properties/name';
    const shortname = 'https://atomicdata.dev/properties/shortname';
    const description = 'https://atomicdata.dev/properties/description';
    const bodySchema = {
      type: 'object',
      properties: {
        prose: { $ref: '#/$defs/Text' },
        list: { $ref: '#/$defs/List' },
      },
      $defs: {
        Text: {
          type: 'object',
          properties: { content: { type: 'string' } },
        },
        List: {
          type: 'object',
          properties: {
            entries: { type: 'array', items: { $ref: '#/$defs/Entry' } },
          },
        },
        Entry: {
          type: 'object',
          properties: {
            selected: { type: 'boolean', title: 'Selected' },
            label: { $ref: '#/$defs/Text', title: 'Item' },
          },
        },
      },
    };

    const property = await store.newResource({
      parent: drive,
      isA: 'https://atomicdata.dev/classes/Property',
      propVals: {
        [name]: 'Body',
        [shortname]: 'body',
        [description]: 'Schema-backed sample text and lists',
        'https://atomicdata.dev/properties/datatype':
          'https://atomicdata.dev/datatypes/json',
        'https://atomicdata.dev/properties/jsonSchema': bodySchema,
      },
    });
    await property.save();

    const rowClass = await store.newResource({
      parent: drive,
      isA: 'https://atomicdata.dev/classes/Class',
      propVals: {
        [name]: 'Sample note',
        [shortname]: 'sample-note',
        [description]: 'Invented records for readable JSON previews',
        'https://atomicdata.dev/properties/recommends': [
          name,
          property.subject,
        ],
      },
    });
    await rowClass.save();

    const table = await store.newResource({
      parent: drive,
      isA: 'https://atomicdata.dev/classes/Table',
      propVals: {
        [name]: 'Schema preview samples',
        'https://atomicdata.dev/properties/classtype': rowClass.subject,
        'https://atomicdata.dev/properties/tableColumnWidths': [200, 650],
      },
    });
    await table.save();

    const prose = {
      prose: {
        content: "Sketch tomorrow's workshop.\nBring paper and blue pencils.",
      },
    };
    const checked = {
      list: {
        entries: [{ selected: true, label: { content: 'Pack the paper' } }],
      },
    };
    const unchecked = {
      list: {
        entries: [
          { selected: false, label: { content: 'Choose blue pencils' } },
        ],
      },
    };

    for (const [title, body] of [
      ['Prose sample', prose],
      ['Checked sample', checked],
      ['Unchecked sample', unchecked],
    ] as const) {
      const row = await store.newResource({
        parent: table.subject,
        isA: rowClass.subject,
        propVals: { [name]: title, [property.subject]: body },
      });
      await row.save();
    }

    return { table: table.subject, checked };
  });

  await page.goto(
    new URL(
      `/app/show?subject=${encodeURIComponent(created.table)}`,
      page.url(),
    ).href,
  );
  await waitForGridInteractive(page);

  const proseCell = page
    .getByRole('row')
    .filter({ hasText: 'Prose sample' })
    .locator('[aria-colindex="3"]');
  const checkedCell = page
    .getByRole('row')
    .filter({ hasText: 'Checked sample' })
    .locator('[aria-colindex="3"]');
  const uncheckedCell = page
    .getByRole('row')
    .filter({ hasText: 'Unchecked sample' })
    .locator('[aria-colindex="3"]');

  await expect(proseCell).toBeVisible();
  await expect(proseCell).toHaveText(
    "Sketch tomorrow's workshop. Bring paper and blue pencils.",
  );
  await expect(proseCell.locator('div')).toHaveCSS('white-space', 'pre-wrap');
  await expect(checkedCell).toHaveText(
    /^[•] Selected: ☑\s+Item: Pack the paper$/,
  );
  await expect(uncheckedCell).toHaveText(
    /^[•] Selected: ☐\s+Item: Choose blue pencils$/,
  );

  for (const cell of [proseCell, checkedCell, uncheckedCell]) {
    await expect(cell).not.toContainText(
      /[{}]|"(?:prose|list|entries|selected|content)"\s*:/,
    );
  }

  await page.screenshot({
    path: testInfo.outputPath('schema-json-table-desktop.png'),
    fullPage: true,
    animations: 'disabled',
  });

  // The readable cell is a preview. Its existing dialog still opens the full
  // source object, including wrappers, field names and the actual boolean.
  await checkedCell.click();
  await checkedCell.press('Enter');
  await page
    .getByRole('button', { name: 'Open edit dialog', exact: true })
    .click();
  const dialog = page.getByRole('dialog');
  await expect(dialog.getByRole('heading', { name: /^Edit / })).toBeVisible();
  const editor = dialog.locator('.cm-content');
  await expect(editor).toBeVisible();
  await expect
    .poll(async () => {
      const lines = await editor.locator('.cm-line').allTextContents();

      try {
        return JSON.parse(lines.join('\n'));
      } catch {
        return undefined;
      }
    })
    .toEqual(created.checked);
  await page.screenshot({
    path: testInfo.outputPath('schema-json-table-editor.png'),
    fullPage: true,
    animations: 'disabled',
  });
  await dialog.press('Escape');
  await expect(dialog).not.toBeVisible();
  await expect(checkedCell).toHaveText(
    /^[•] Selected: ☑\s+Item: Pack the paper$/,
  );
});

import * as vscode from 'vscode'
import {
  DEFAULT_PERMISSIONS,
  parsePermissionValue,
  type PermissionCategory,
  type PermissionPolicy,
  type PermissionValue,
} from '@repo/legalese-agent'

/**
 * VS Code settings key for each permission category. Values persist
 * under `legaleseAi.permissions.*` so they survive reloads and flow
 * through settings-sync.
 */
const CATEGORY_SETTING: Record<PermissionCategory, string> = {
  'fs.read': 'legaleseAi.permissions.readFiles',
  'fs.create': 'legaleseAi.permissions.createFiles',
  'fs.edit': 'legaleseAi.permissions.editFiles',
  'fs.delete': 'legaleseAi.permissions.deleteFiles',
  'l4.evaluate': 'legaleseAi.permissions.evaluateL4',
  'l4.refactor': 'legaleseAi.permissions.refactorL4',
  'mcp.l4Rules': 'legaleseAi.permissions.runDeployedRules',
  'mcp.vscode': 'legaleseAi.permissions.vscodeMcp',
  'meta.askUser': 'legaleseAi.permissions.askUser',
  'meta.statusUpdate': 'legaleseAi.permissions.statusUpdate',
}

/** {@link PermissionPolicy} backed by the user's VS Code settings, with
 *  the core's defaults when a setting is unset or invalid. Read fresh
 *  on every call so a settings change applies to the next tool call. */
export class SettingsPermissionPolicy implements PermissionPolicy {
  getPermission(category: PermissionCategory): PermissionValue {
    const raw = vscode.workspace
      .getConfiguration()
      .get<string>(CATEGORY_SETTING[category])
    return parsePermissionValue(raw) ?? DEFAULT_PERMISSIONS[category]
  }

  async setPermission(
    category: PermissionCategory,
    value: PermissionValue
  ): Promise<void> {
    await vscode.workspace
      .getConfiguration()
      .update(
        CATEGORY_SETTING[category],
        value,
        vscode.ConfigurationTarget.Global
      )
  }
}

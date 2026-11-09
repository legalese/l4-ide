import { config } from '@repo/eslint-config/base'

export default [...config, { ignores: ['dist/**', 'out/**'] }]

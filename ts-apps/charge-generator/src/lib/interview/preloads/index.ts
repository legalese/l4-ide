import type { Preload } from '../preload'
import { LEWIS_CHRISTINE } from './lewis-christine'
import { SARJIT_SINGH } from './sarjit-singh'
import { CHEN_WEIXIONG } from './chen-weixiong'
import { CHEN_WEIXIONG_ATTEMPT } from './chen-weixiong-attempt'
import { CARL_ELIAS_MOSES } from './carl-elias-moses'
import { CARL_ELIAS_MOSES_AMENDED } from './carl-elias-moses-amended'
import { CHAN_YOK_TUANG } from './chan-yok-tuang'
import { ANG_BOON_HAN } from './ang-boon-han'
import { LIM_WEI_MING } from './lim-wei-ming'

/** One per bench case. Order = the widget's cycle order: positives, then the two refusals. */
export const PRELOADS: readonly Preload[] = [
  LEWIS_CHRISTINE,
  SARJIT_SINGH,
  CHEN_WEIXIONG,
  CHEN_WEIXIONG_ATTEMPT,
  CARL_ELIAS_MOSES,
  CARL_ELIAS_MOSES_AMENDED,
  CHAN_YOK_TUANG,
  ANG_BOON_HAN,
  LIM_WEI_MING,
]

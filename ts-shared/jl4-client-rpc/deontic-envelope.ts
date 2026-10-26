/**
 * Whether a function takes the DEONTIC simulation envelope: `startTime` and
 * `events` beside its inputs. The deploy sidebar needs it to strip those two
 * from both sides of its schema diff, since the deployed schema has them and the
 * language server's does not.
 *
 * The answer is a flag that the function's type decided: the service computes
 * it when it exports the function (`isDeontic` in a function's summary) and the
 * language server computes it for the local one. It is not a property of how
 * the return type is spelled: `PROVISION OF P, A`, the deprecated alias of
 * `DEONTIC P A`, is the same type and takes the same envelope, and its display
 * name does not begin with "DEONTIC".
 */
export interface MaybeDeontic {
  /** The flag, from the function's type. Absent from a deployment that a
   *  service stored before it kept one. */
  isDeontic?: boolean
  /** Display name of the return type. Read only when there is no flag. */
  returnType?: string
}

/**
 * The flag when there is one. Without it (an older deployment) the display name
 * of the return type, as the service itself reads it for a stored deployment
 * that has no flag: `DEONTIC`, or `PROVISION OF`. That is a guess about how a
 * type was written, kept for old data only.
 */
export function isDeonticFunction(fn: MaybeDeontic): boolean {
  if (typeof fn.isDeontic === 'boolean') return fn.isDeontic
  const returnType = fn.returnType ?? ''
  return (
    returnType.startsWith('DEONTIC') || returnType.startsWith('PROVISION OF')
  )
}

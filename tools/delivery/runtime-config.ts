import {
  loadOrchestratorConfig as loadOrchestratorConfigImpl,
  resolveOrchestratorConfig as resolveOrchestratorConfigImpl,
  inferPackageManager,
  VALID_REVIEW_POLICY_STAGE_VALUES,
  type CodogotchiConfig,
  type OrchestratorConfig,
  type PrReviewAgent,
  type ResolvedOrchestratorConfig,
  type ResolvedReviewPolicy,
  type ReviewPolicy,
  type ReviewPolicyStageValue,
} from './config';

export type {
  CodogotchiConfig,
  OrchestratorConfig,
  PrReviewAgent,
  ResolvedOrchestratorConfig,
  ResolvedReviewPolicy,
  ReviewPolicy,
  ReviewPolicyStageValue,
};

export { inferPackageManager, VALID_REVIEW_POLICY_STAGE_VALUES };

export async function loadOrchestratorConfig(
  cwd: string,
): Promise<OrchestratorConfig> {
  return loadOrchestratorConfigImpl(cwd);
}

export function resolveOrchestratorConfig(
  raw: OrchestratorConfig,
  cwd: string,
): ResolvedOrchestratorConfig {
  return resolveOrchestratorConfigImpl(raw, cwd);
}

export function generateRunDeliverInvocation(
  packageManager: ResolvedOrchestratorConfig['packageManager'],
): string {
  if (packageManager === 'npm') {
    return 'npm run deliver --';
  }

  return `${packageManager} run deliver`;
}

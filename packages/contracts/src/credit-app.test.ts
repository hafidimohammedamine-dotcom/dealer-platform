import { describe, expect, it } from 'vitest';
import { CreditAppSchema } from './index.js';
import { ID, T, ok, samples, without } from './test-samples.js';

const joint = {
  has_coapplicant: true,
  coapplicant_customer_id: ID.customer2,
  joint_intent_evidence: { evidence_text: 'We apply together.', recorded_at: T },
};
const cpa = samples.creditApp.value.credit_pull_authorization;

describe('credit app', () => {
  it('uses the fake 900 range for SSNs in the sample', () => {
    expect(samples.creditApp.value.ssn.startsWith('900-')).toBe(true);
  });
  it('limits the applicant and employer names', () => {
    expect(ok('creditApp', { applicant_name: 'x'.repeat(200) })).toBe(true);
    expect(ok('creditApp', { applicant_name: 'x'.repeat(201) })).toBe(false);
    expect(ok('creditApp', { applicant_name: '' })).toBe(false);
    expect(ok('creditApp', { applicant_name: 'José 李 Müller' })).toBe(true);
    expect(ok('creditApp', { applicant_name: 'a‮b' })).toBe(false);
    expect(ok('creditApp', { employer_name: 'x'.repeat(200) })).toBe(true);
    expect(ok('creditApp', { employer_name: 'x'.repeat(201) })).toBe(false);
  });
  it('checks the bank, income and date of birth formats', () => {
    expect(ok('creditApp', { bank_routing_number: '12345678' })).toBe(false);
    expect(ok('creditApp', { bank_account_number: '123' })).toBe(false);
    expect(ok('creditApp', { date_of_birth: '1980-13-01' })).toBe(false);
    expect(ok('creditApp', { monthly_income_cents: 0 })).toBe(true);
  });
});

describe('credit app authorization', () => {
  it('requires the credit pull authorization with wording, time and method', () => {
    expect(
      CreditAppSchema.safeParse(without('creditApp', 'credit_pull_authorization')).success,
    ).toBe(false);
    expect(ok('creditApp', { credit_pull_authorization: { ...cpa, evidence_text: '' } })).toBe(
      false,
    );
    expect(ok('creditApp', { credit_pull_authorization: { ...cpa, method: 'wink' } })).toBe(false);
    expect(ok('creditApp', { credit_pull_authorization: { ...cpa, authorized_at: 'x' } })).toBe(
      false,
    );
  });
  it('limits the authorization wording to 2000 characters', () => {
    const text = (n: number) => ({
      credit_pull_authorization: { ...cpa, evidence_text: 'x'.repeat(n) },
    });
    expect(ok('creditApp', text(2000))).toBe(true);
    expect(ok('creditApp', text(2001))).toBe(false);
  });
  it('rejects unknown keys in the authorization', () => {
    expect(ok('creditApp', { credit_pull_authorization: { ...cpa, extra: 1 } })).toBe(false);
  });
});

describe('credit app co-applicant', () => {
  it('requires the co-applicant customer and joint intent evidence when has_coapplicant', () => {
    expect(ok('creditApp', joint)).toBe(true);
    expect(ok('creditApp', { ...joint, coapplicant_customer_id: undefined })).toBe(false);
    expect(ok('creditApp', { ...joint, joint_intent_evidence: undefined })).toBe(false);
    expect(ok('creditApp', { has_coapplicant: true })).toBe(false);
    expect(ok('creditApp', { ...joint, coapplicant_customer_id: '../c2' })).toBe(false);
  });
  it('limits the joint intent wording to 2000 characters', () => {
    const intent = (n: number) => ({
      ...joint,
      joint_intent_evidence: { evidence_text: 'x'.repeat(n), recorded_at: T },
    });
    expect(ok('creditApp', intent(2000))).toBe(true);
    expect(ok('creditApp', intent(2001))).toBe(false);
    expect(ok('creditApp', intent(0))).toBe(false);
  });
  it('rejects co-applicant fields when has_coapplicant is false', () => {
    expect(ok('creditApp', { coapplicant_customer_id: ID.customer2 })).toBe(false);
    expect(ok('creditApp', { joint_intent_evidence: joint.joint_intent_evidence })).toBe(false);
  });
});

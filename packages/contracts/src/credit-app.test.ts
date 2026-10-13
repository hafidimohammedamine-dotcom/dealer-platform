import { describe, expect, it } from 'vitest';
import { CreditAppSchema } from './index.js';
import { T, ok, samples, without } from './samples.test.js';

const joint = {
  has_coapplicant: true,
  coapplicant_customer_id: 'c2',
  joint_intent_evidence: { evidence_text: 'We apply together.', recorded_at: T },
};
const cpa = samples.creditApp.value.credit_pull_authorization;

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
  it('limits the authorization wording to 2000 characters and rejects unknown keys', () => {
    const wording = (evidence_text: string) => ({
      credit_pull_authorization: { ...cpa, evidence_text },
    });
    expect(ok('creditApp', wording('x'.repeat(2000)))).toBe(true);
    expect(ok('creditApp', wording('x'.repeat(2001)))).toBe(false);
    expect(ok('creditApp', wording('I agree\u0000'))).toBe(false);
    expect(ok('creditApp', { credit_pull_authorization: { ...cpa, surprise: 1 } })).toBe(false);
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
  it('limits the joint intent wording to 1-2000 characters', () => {
    const wording = (evidence_text: string) => ({
      ...joint,
      joint_intent_evidence: { evidence_text, recorded_at: T },
    });
    expect(ok('creditApp', wording('x'.repeat(2000)))).toBe(true);
    expect(ok('creditApp', wording('x'.repeat(2001)))).toBe(false);
    expect(ok('creditApp', wording(''))).toBe(false);
  });
  it('rejects co-applicant fields when has_coapplicant is false', () => {
    expect(ok('creditApp', { coapplicant_customer_id: 'c2' })).toBe(false);
    expect(ok('creditApp', { joint_intent_evidence: joint.joint_intent_evidence })).toBe(false);
  });
});

describe('credit app text fields', () => {
  it('limits applicant_name to 1-200 characters and accepts Unicode', () => {
    expect(ok('creditApp', { applicant_name: '' })).toBe(false);
    expect(ok('creditApp', { applicant_name: 'x'.repeat(200) })).toBe(true);
    expect(ok('creditApp', { applicant_name: 'x'.repeat(201) })).toBe(false);
    expect(ok('creditApp', { applicant_name: 'Zoë 李小龍 Müller' })).toBe(true);
    expect(ok('creditApp', { applicant_name: 'Ann\nTest' })).toBe(false);
  });
  it('limits employer_name to 200 characters', () => {
    expect(ok('creditApp', { employer_name: 'x'.repeat(200) })).toBe(true);
    expect(ok('creditApp', { employer_name: 'x'.repeat(201) })).toBe(false);
  });
  it('checks the bank fields', () => {
    expect(ok('creditApp', { bank_account_number: '123' })).toBe(false);
    expect(ok('creditApp', { bank_account_number: '1'.repeat(17) })).toBe(true);
    expect(ok('creditApp', { bank_account_number: '1'.repeat(18) })).toBe(false);
    expect(ok('creditApp', { bank_routing_number: '12345678' })).toBe(false);
  });
});

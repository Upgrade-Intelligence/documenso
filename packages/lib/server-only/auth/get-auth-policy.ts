import { AppError, AppErrorCode } from '@documenso/lib/errors/app-error';
import { env } from '@documenso/lib/utils/env';

const parseCsvEnv = (value?: string) =>
  value
    ?.split(',')
    .map((entry) => entry.trim().toLowerCase())
    .filter(Boolean) ?? [];

export type AuthPolicy = {
  isGoogleOAuthOnly: boolean;
  allowedAuthEmails: string[];
  allowedAuthDomains: string[];
};

export const getAuthPolicy = (): AuthPolicy => ({
  isGoogleOAuthOnly: env('NEXT_PRIVATE_AUTH_GOOGLE_ONLY') === 'true',
  allowedAuthEmails: parseCsvEnv(env('NEXT_PRIVATE_AUTH_ALLOWED_EMAILS')),
  allowedAuthDomains: parseCsvEnv(env('NEXT_PRIVATE_AUTH_ALLOWED_EMAIL_DOMAINS')),
});

export const isGoogleOAuthOnlyEnabled = () => getAuthPolicy().isGoogleOAuthOnly;

export const isGoogleOAuthEmailAllowed = (email: string, authPolicy = getAuthPolicy()) => {
  const normalizedEmail = email.trim().toLowerCase();
  const emailDomain = normalizedEmail.split('@')[1] ?? '';
  const hasRestrictions =
    authPolicy.allowedAuthEmails.length > 0 || authPolicy.allowedAuthDomains.length > 0;

  if (!hasRestrictions) {
    return true;
  }

  return (
    authPolicy.allowedAuthEmails.includes(normalizedEmail) ||
    authPolicy.allowedAuthDomains.includes(emailDomain)
  );
};

export const getPrimaryAllowedAuthDomain = () => getAuthPolicy().allowedAuthDomains[0];

export const assertGoogleOAuthOnlyDisabled = () => {
  if (!isGoogleOAuthOnlyEnabled()) {
    return;
  }

  throw new AppError(AppErrorCode.UNAUTHORIZED, {
    message: 'Only Google OAuth sign-in is enabled',
    userMessage: 'Sign in with Google to access this workspace.',
    statusCode: 401,
  });
};

export const assertGoogleOAuthProviderAllowed = (provider: string) => {
  if (!isGoogleOAuthOnlyEnabled() || provider === 'google') {
    return;
  }

  throw new AppError(AppErrorCode.UNAUTHORIZED, {
    message: `OAuth provider "${provider}" is not allowed`,
    userMessage: 'Sign in with Google to access this workspace.',
    statusCode: 401,
  });
};

export const assertGoogleOAuthEmailAllowed = (email: string) => {
  if (isGoogleOAuthEmailAllowed(email)) {
    return;
  }

  throw new AppError(AppErrorCode.UNAUTHORIZED, {
    message: `Email "${email}" is not allowed to sign in`,
    userMessage: 'Only approved @usetomo.com accounts can sign in.',
    statusCode: 401,
  });
};

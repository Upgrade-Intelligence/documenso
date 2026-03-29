import type { Context } from 'hono';
import { Hono } from 'hono';

import { AppError, AppErrorCode } from '@documenso/lib/errors/app-error';

import { GoogleAuthOptions, MicrosoftAuthOptions, OidcAuthOptions } from '../config';
import { handleOAuthCallbackUrl } from '../lib/utils/handle-oauth-callback-url';
import { handleOAuthOrganisationCallbackUrl } from '../lib/utils/handle-oauth-organisation-callback-url';
import type { HonoAuthContext } from '../types/context';

const handleOauthCallbackError = (err: unknown, c: Context) => {
  const error =
    err instanceof AppError
      ? err
      : new AppError(AppErrorCode.UNKNOWN_ERROR, {
          message: err instanceof Error ? err.message : 'Unknown OAuth callback error',
          userMessage: 'Unable to sign in right now. Please try again.',
          statusCode: 500,
        });

  const hashParams = new URLSearchParams({
    authErrorCode: error.code,
    authErrorMessage:
      error.userMessage ??
      (error.statusCode && error.statusCode >= 500
        ? 'Unable to sign in right now. Please try again.'
        : error.message),
  });

  return c.redirect(`/signin#${hashParams.toString()}`, 302);
};

/**
 * Have to create this route instead of bundling callback with oauth routes to provide
 * backwards compatibility for self-hosters (since we used to use NextAuth).
 */
export const callbackRoute = new Hono<HonoAuthContext>()
  /**
   * OIDC callback verification.
   */
  .get('/oidc', async (c) => {
    try {
      return await handleOAuthCallbackUrl({ c, clientOptions: OidcAuthOptions });
    } catch (err) {
      return handleOauthCallbackError(err, c);
    }
  })

  /**
   * Organisation OIDC callback verification.
   */
  .get('/oidc/org/:orgUrl', async (c) => {
    const orgUrl = c.req.param('orgUrl');

    try {
      return await handleOAuthOrganisationCallbackUrl({
        c,
        orgUrl,
      });
    } catch (err) {
      console.error(err);

      if (err instanceof Error) {
        throw new AppError(err.name, {
          message: err.message,
          statusCode: 500,
        });
      }

      throw err;
    }
  })

  /**
   * Google callback verification.
   */
  .get('/google', async (c) => {
    try {
      return await handleOAuthCallbackUrl({ c, clientOptions: GoogleAuthOptions });
    } catch (err) {
      return handleOauthCallbackError(err, c);
    }
  })

  /**
   * Microsoft callback verification.
   */
  .get('/microsoft', async (c) => {
    try {
      return await handleOAuthCallbackUrl({ c, clientOptions: MicrosoftAuthOptions });
    } catch (err) {
      return handleOauthCallbackError(err, c);
    }
  });

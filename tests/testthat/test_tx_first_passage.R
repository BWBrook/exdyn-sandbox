test_that("extirpation time records first passage from above", {
  N <- array(c(5, 4, 3, 1, 0), dim = c(1, 1, 5))
  res <- exdyn.sandbox:::exdyn_extirpation_time(N, K0 = 100, frac = 0.02, adaptive = FALSE)
  expect_equal(res[1, 1], 4)
})

test_that("cells starting below threshold do not get early extirpation", {
  N <- array(c(1, 1, 1, 1), dim = c(1, 1, 4))
  res <- exdyn.sandbox:::exdyn_extirpation_time(N, K0 = 100, frac = 0.02, adaptive = FALSE)
  expect_true(is.na(res[1, 1]))

  N2 <- array(c(1, 5, 6, 1, 0), dim = c(1, 1, 5))
  res2 <- exdyn.sandbox:::exdyn_extirpation_time(N2, K0 = 100, frac = 0.02, adaptive = FALSE)
  expect_equal(res2[1, 1], 4)
})

test_that("adaptive thresholds scale with initial abundance", {
  N <- array(0, dim = c(2, 1, 5))
  N[1, 1, ] <- c(10, 9, 8, 1.5, 0.5)
  N[2, 1, ] <- c(1, 1.2, 0.4, 0.2, 0.1)

  res_adapt <- exdyn.sandbox:::exdyn_extirpation_time(N, K0 = 100, frac = 0.02, adaptive = TRUE, rel0 = 0.5)
  res_fixed <- exdyn.sandbox:::exdyn_extirpation_time(N, K0 = 100, frac = 0.02, adaptive = FALSE)

  expect_equal(res_adapt[1, 1], 4)
  expect_equal(res_adapt[2, 1], 3)
  expect_true(is.na(res_fixed[2, 1]))
})

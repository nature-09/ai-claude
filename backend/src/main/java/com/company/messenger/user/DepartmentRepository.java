package com.company.messenger.user;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

public interface DepartmentRepository extends JpaRepository<Department, Long> {

    List<Department> findAllByOrderBySortOrderAscNameAsc();

    Optional<Department> findFirstByName(String name);

    boolean existsByParentId(Long parentId);
}
